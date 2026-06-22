import 'package:flutter_test/flutter_test.dart';
import 'package:nice_view/services/app_exceptions.dart';
import 'package:nice_view/services/rate_limiter.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test('acquire enforces min gap and sliding window', () async {
    SharedPreferences.setMockInitialValues({});
    final preferences = await SharedPreferences.getInstance();
    var now = DateTime(2026, 6, 21, 10);
    final waits = <Duration>[];
    final limiter = RateLimiter(
      preferences,
      config: const RateLimiterConfig(
        window: Duration(seconds: 5),
        maxPerWindow: 2,
        minGap: Duration(milliseconds: 1500),
        lockout: Duration(minutes: 30),
      ),
      now: () => now,
      sleep: (duration) async {
        waits.add(duration);
        now = now.add(duration);
      },
    );

    await limiter.acquire();
    expect(limiter.state.used, 1);

    now = now.add(const Duration(milliseconds: 500));
    await limiter.acquire();
    expect(waits.single, const Duration(milliseconds: 1000));
    expect(limiter.state.used, 2);

    now = now.add(const Duration(milliseconds: 1500));
    await limiter.acquire();
    expect(waits.last, const Duration(seconds: 2));
    expect(limiter.state.used, 2);
    expect(limiter.state.remaining, 0);
  });

  test('default config allows at most 90 requests per 300 seconds', () async {
    SharedPreferences.setMockInitialValues({});
    final preferences = await SharedPreferences.getInstance();
    var now = DateTime(2026, 6, 21, 10);
    final waits = <Duration>[];
    final limiter = RateLimiter(
      preferences,
      now: () => now,
      sleep: (duration) async {
        waits.add(duration);
        now = now.add(duration);
      },
    );

    for (var i = 0; i < defaultMaxPerWindow; i += 1) {
      await limiter.acquire();
    }

    expect(limiter.state.used, defaultMaxPerWindow);
    expect(limiter.state.remaining, 0);
    await limiter.acquire();
    expect(waits, contains(const Duration(milliseconds: 166500)));
    expect(limiter.state.used, defaultMaxPerWindow);
  });

  test('noteLockout blocks acquire for 30 minutes and persists state', () async {
    SharedPreferences.setMockInitialValues({});
    final preferences = await SharedPreferences.getInstance();
    var now = DateTime(2026, 6, 21, 11);
    final limiter = RateLimiter(
      preferences,
      now: () => now,
      sleep: (duration) async {
        now = now.add(duration);
      },
    );

    await limiter.noteLockout();

    expect(limiter.state.isLockout, isTrue);
    expect(limiter.state.lockoutRemaining, const Duration(minutes: 30));
    await expectLater(limiter.acquire(), throwsA(isA<ServerLockoutException>()));

    final restored = RateLimiter(
      preferences,
      now: () => now.add(const Duration(minutes: 5)),
    );
    expect(restored.state.isLockout, isTrue);
    expect(restored.state.lockoutRemaining, const Duration(minutes: 25));
  });

  test('clearLockout removes persisted server lockout', () async {
    SharedPreferences.setMockInitialValues({});
    final preferences = await SharedPreferences.getInstance();
    final now = DateTime(2026, 6, 21, 12);
    final limiter = RateLimiter(
      preferences,
      now: () => now,
    );

    await limiter.noteLockout();
    expect(limiter.state.isLockout, isTrue);

    await limiter.clearLockout();

    expect(limiter.state.isLockout, isFalse);
    final restored = RateLimiter(
      preferences,
      now: () => now.add(const Duration(minutes: 1)),
    );
    expect(restored.state.isLockout, isFalse);
  });
}
