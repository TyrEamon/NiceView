import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'app_exceptions.dart';
import 'shared_preferences_provider.dart';

const defaultWindowSeconds = 300;
const defaultMaxPerWindow = 90;
const defaultMinGapMs = 1500;
const defaultLockoutMinutes = 30;

final rateLimiterProvider =
    StateNotifierProvider<RateLimiter, RateLimiterState>((ref) {
  return RateLimiter(ref.watch(sharedPreferencesProvider));
});

class RateLimiterConfig {
  const RateLimiterConfig({
    this.window = const Duration(seconds: defaultWindowSeconds),
    this.maxPerWindow = defaultMaxPerWindow,
    this.minGap = const Duration(milliseconds: defaultMinGapMs),
    this.lockout = const Duration(minutes: defaultLockoutMinutes),
  });

  final Duration window;
  final int maxPerWindow;
  final Duration minGap;
  final Duration lockout;
}

class RateLimiterState {
  const RateLimiterState({
    required this.config,
    required this.requestEvents,
    required this.updatedAt,
    this.lastRequestAt,
    this.lockoutUntil,
  });

  factory RateLimiterState.initial(
    RateLimiterConfig config, {
    required DateTime updatedAt,
  }) {
    return RateLimiterState(
      config: config,
      requestEvents: const [],
      updatedAt: updatedAt,
    );
  }

  final RateLimiterConfig config;
  final List<DateTime> requestEvents;
  final DateTime updatedAt;
  final DateTime? lastRequestAt;
  final DateTime? lockoutUntil;

  int get used => activeEvents().length;

  int get remaining {
    final value = config.maxPerWindow - used;
    if (value < 0) {
      return 0;
    }
    if (value > config.maxPerWindow) {
      return config.maxPerWindow;
    }
    return value;
  }

  bool get isLockout => lockoutRemaining > Duration.zero;

  Duration get lockoutRemaining {
    final until = lockoutUntil;
    if (until == null) {
      return Duration.zero;
    }
    final remaining = until.difference(updatedAt);
    return remaining.isNegative ? Duration.zero : remaining;
  }

  Duration? get timeUntilNextAvailable {
    final lockout = lockoutRemaining;
    if (lockout > Duration.zero) {
      return lockout;
    }

    final active = activeEvents()..sort();
    if (active.length >= config.maxPerWindow) {
      return _positive(active.first.add(config.window).difference(updatedAt));
    }

    final last = lastRequestAt;
    if (last == null) {
      return null;
    }
    return _positive(last.add(config.minGap).difference(updatedAt));
  }

  List<DateTime> activeEvents([DateTime? at]) {
    final now = at ?? updatedAt;
    final earliest = now.subtract(config.window);
    return requestEvents.where((event) => event.isAfter(earliest)).toList();
  }

  RateLimiterState copyWith({
    RateLimiterConfig? config,
    List<DateTime>? requestEvents,
    DateTime? updatedAt,
    Object? lastRequestAt = _unset,
    Object? lockoutUntil = _unset,
  }) {
    return RateLimiterState(
      config: config ?? this.config,
      requestEvents: requestEvents ?? this.requestEvents,
      updatedAt: updatedAt ?? this.updatedAt,
      lastRequestAt: identical(lastRequestAt, _unset)
          ? this.lastRequestAt
          : lastRequestAt as DateTime?,
      lockoutUntil: identical(lockoutUntil, _unset)
          ? this.lockoutUntil
          : lockoutUntil as DateTime?,
    );
  }

  static Duration? _positive(Duration value) {
    if (value <= Duration.zero) {
      return null;
    }
    return value;
  }
}

const _unset = Object();

class RateLimiter extends StateNotifier<RateLimiterState> {
  RateLimiter(
    this._preferences, {
    RateLimiterConfig config = const RateLimiterConfig(),
    DateTime Function()? now,
    Future<void> Function(Duration duration)? sleep,
  })  : _config = config,
        _now = now ?? DateTime.now,
        _sleep = sleep ?? ((duration) => Future<void>.delayed(duration)),
        super(
          RateLimiterState.initial(
            config,
            updatedAt: (now ?? DateTime.now)(),
          ),
        ) {
    state = _loadState();
  }

  static const _eventsKey = 'nice_view.rate_limiter_events';
  static const _lastRequestKey = 'nice_view.rate_limiter_last_request_at';
  static const _lockoutKey = 'nice_view.rate_limiter_lockout_until';

  final SharedPreferences _preferences;
  final RateLimiterConfig _config;
  final DateTime Function() _now;
  final Future<void> Function(Duration duration) _sleep;
  Future<void> _tail = Future<void>.value();

  RateLimiterState get currentState => state;

  Future<void> acquire() {
    final ready = _ignoreTailError(_tail);
    final operation = ready.then((_) => _acquireLocked());
    _tail = _ignoreTailError(operation);
    return operation;
  }

  Future<void> _ignoreTailError(Future<void> future) async {
    try {
      await future;
    } catch (_) {}
  }

  Future<void> noteLockout() async {
    final now = _now();
    state = _prunedState(now).copyWith(
      updatedAt: now,
      lockoutUntil: now.add(_config.lockout),
    );
    await _saveState();
  }

  Future<void> refresh() async {
    state = _prunedState(_now());
    await _saveState();
  }

  Future<void> _acquireLocked() async {
    while (true) {
      final now = _now();
      final current = _prunedState(now);
      state = current;

      if (current.isLockout) {
        throw ServerLockoutException(
          '已触发服务器冷却，约 ${current.lockoutRemaining.inMinutes} 分钟后再试',
        );
      }

      final active = current.activeEvents()..sort();
      if (active.length >= _config.maxPerWindow) {
        final wait = active.first.add(_config.window).difference(now);
        state = current.copyWith(updatedAt: now);
        await _sleep(wait <= Duration.zero ? Duration.zero : wait);
        continue;
      }

      final last = current.lastRequestAt;
      if (last != null) {
        final wait = last.add(_config.minGap).difference(now);
        if (wait > Duration.zero) {
          state = current.copyWith(updatedAt: now);
          await _sleep(wait);
          continue;
        }
      }

      final grantedAt = _now();
      final nextEvents = current.activeEvents(grantedAt)..add(grantedAt);
      state = current.copyWith(
        requestEvents: nextEvents,
        updatedAt: grantedAt,
        lastRequestAt: grantedAt,
      );
      await _saveState();
      return;
    }
  }

  RateLimiterState _loadState() {
    final now = _now();
    final events = (_preferences.getStringList(_eventsKey) ?? const [])
        .map(DateTime.tryParse)
        .whereType<DateTime>()
        .toList();
    final lastRequest = DateTime.tryParse(
      _preferences.getString(_lastRequestKey) ?? '',
    );
    final lockout = DateTime.tryParse(_preferences.getString(_lockoutKey) ?? '');

    return RateLimiterState(
      config: _config,
      requestEvents: events,
      updatedAt: now,
      lastRequestAt: lastRequest,
      lockoutUntil: lockout,
    ).copyWith(
      requestEvents: _activeEvents(events, now),
      lockoutUntil: lockout != null && now.isBefore(lockout) ? lockout : null,
    );
  }

  RateLimiterState _prunedState(DateTime now) {
    final lockout = state.lockoutUntil;
    return state.copyWith(
      updatedAt: now,
      requestEvents: _activeEvents(state.requestEvents, now),
      lockoutUntil: lockout != null && now.isBefore(lockout) ? lockout : null,
    );
  }

  List<DateTime> _activeEvents(List<DateTime> events, DateTime now) {
    final earliest = now.subtract(_config.window);
    return events.where((event) => event.isAfter(earliest)).toList();
  }

  Future<void> _saveState() async {
    final current = _prunedState(_now());
    await _preferences.setStringList(
      _eventsKey,
      current.requestEvents.map((event) => event.toIso8601String()).toList(),
    );
    final lastRequest = current.lastRequestAt;
    if (lastRequest == null) {
      await _preferences.remove(_lastRequestKey);
    } else {
      await _preferences.setString(
        _lastRequestKey,
        lastRequest.toIso8601String(),
      );
    }

    final lockout = current.lockoutUntil;
    if (lockout == null) {
      await _preferences.remove(_lockoutKey);
    } else {
      await _preferences.setString(_lockoutKey, lockout.toIso8601String());
    }
    state = current;
  }
}
