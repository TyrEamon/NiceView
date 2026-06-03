import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../app/theme.dart';
import '../data/tag_library_repository.dart';
import '../domain/tag_info.dart';

enum _TagSortMode { count, alphabet }

class TagLibraryPage extends ConsumerStatefulWidget {
  const TagLibraryPage({super.key});

  @override
  ConsumerState<TagLibraryPage> createState() => _TagLibraryPageState();
}

class _TagLibraryPageState extends ConsumerState<TagLibraryPage> {
  static const _letters = [
    '全部',
    'A',
    'B',
    'C',
    'D',
    'E',
    'F',
    'G',
    'H',
    'I',
    'J',
    'K',
    'L',
    'M',
    'N',
    'O',
    'P',
    'Q',
    'R',
    'S',
    'T',
    'U',
    'V',
    'W',
    'X',
    'Y',
    'Z',
    '0-9',
    '其他',
  ];

  late final TextEditingController _searchController;
  Timer? _searchDebounce;
  List<TagInfo> _allTags = const [];
  List<TagInfo> _visibleTags = const [];
  DateTime? _fetchedAt;
  String _query = '';
  String _letter = '全部';
  _TagSortMode _sortMode = _TagSortMode.count;
  bool _isLoading = true;
  bool _isRefreshing = false;
  String? _errorMessage;

  @override
  void initState() {
    super.initState();
    _searchController = TextEditingController();
    unawaited(_load());
  }

  @override
  void dispose() {
    _searchDebounce?.cancel();
    _searchController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: niceBlack,
      appBar: AppBar(
        backgroundColor: niceBlack,
        foregroundColor: niceText,
        title: const Text('标签库'),
        actions: [
          IconButton(
            tooltip: '刷新标签',
            onPressed: _isRefreshing ? null : () => unawaited(_refresh()),
            icon: _isRefreshing
                ? const SizedBox.square(
                    dimension: 20,
                    child: CircularProgressIndicator(strokeWidth: 2),
                  )
                : const Icon(Icons.refresh_rounded),
          ),
        ],
      ),
      body: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 8, 16, 10),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                _SummaryLine(
                  total: _allTags.length,
                  visible: _visibleTags.length,
                  fetchedAt: _fetchedAt,
                ),
                const SizedBox(height: 12),
                TextField(
                  controller: _searchController,
                  style: const TextStyle(color: niceText),
                  textInputAction: TextInputAction.search,
                  decoration: InputDecoration(
                    hintText: '搜索标签名称...',
                    prefixIcon: const Icon(Icons.search_rounded),
                    suffixIcon: _searchController.text.isEmpty
                        ? null
                        : IconButton(
                            onPressed: _clearSearch,
                            icon: const Icon(Icons.close_rounded),
                          ),
                    filled: true,
                    fillColor: Colors.white.withValues(alpha: 0.07),
                    border: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(8),
                      borderSide: BorderSide.none,
                    ),
                  ),
                  onChanged: _handleSearchChanged,
                ),
                const SizedBox(height: 12),
                Row(
                  children: [
                    Expanded(
                      child: _LetterStrip(
                        letters: _letters,
                        selected: _letter,
                        onSelected: (letter) {
                          setState(() {
                            _letter = letter;
                            _applyFilters();
                          });
                        },
                      ),
                    ),
                    const SizedBox(width: 10),
                    _SortButton(
                      mode: _sortMode,
                      onChanged: (mode) {
                        setState(() {
                          _sortMode = mode;
                          _applyFilters();
                        });
                      },
                    ),
                  ],
                ),
              ],
            ),
          ),
          Expanded(child: _buildBody()),
        ],
      ),
    );
  }

  Widget _buildBody() {
    if (_isLoading) {
      return const Center(
        child: SizedBox.square(
          dimension: 32,
          child: CircularProgressIndicator(strokeWidth: 2.4),
        ),
      );
    }
    final error = _errorMessage;
    if (error != null && _allTags.isEmpty) {
      return _ErrorView(
        message: error,
        onRetry: () => unawaited(_refresh()),
      );
    }
    if (_visibleTags.isEmpty) {
      return const Center(
        child: Text('没有匹配标签', style: TextStyle(color: niceMuted)),
      );
    }
    return ListView.builder(
      keyboardDismissBehavior: ScrollViewKeyboardDismissBehavior.onDrag,
      itemCount: _visibleTags.length,
      itemExtent: 58,
      itemBuilder: (context, index) {
        final tag = _visibleTags[index];
        return ListTile(
          title: Text(
            tag.name,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: const TextStyle(
              color: niceText,
              fontWeight: FontWeight.w600,
            ),
          ),
          subtitle: tag.sortCount <= 0
              ? null
              : Text(
                  '${tag.sortCount} 图集',
                  style: const TextStyle(color: niceMuted, fontSize: 12),
                ),
          trailing: const Icon(Icons.add_rounded, color: niceMuted),
          onTap: () => _selectTag(tag.name),
        );
      },
    );
  }

  Future<void> _load() async {
    final repository = ref.read(tagLibraryRepositoryProvider);
    final cached = await repository.loadCached();
    if (!mounted) {
      return;
    }
    if (cached != null && cached.tags.isNotEmpty) {
      setState(() {
        _allTags = cached.tags;
        _fetchedAt = cached.fetchedAt;
        _isLoading = false;
        _errorMessage = null;
        _applyFilters();
      });
      return;
    }
    await _refresh();
  }

  Future<void> _refresh() async {
    if (_isRefreshing) {
      return;
    }
    setState(() {
      _isRefreshing = true;
      _errorMessage = null;
      if (_allTags.isEmpty) {
        _isLoading = true;
      }
    });

    try {
      final snapshot = await ref.read(tagLibraryRepositoryProvider).refresh();
      if (!mounted) {
        return;
      }
      setState(() {
        _allTags = snapshot.tags;
        _fetchedAt = snapshot.fetchedAt;
        _isLoading = false;
        _isRefreshing = false;
        _errorMessage = null;
        _applyFilters();
      });
    } catch (error) {
      if (!mounted) {
        return;
      }
      setState(() {
        _isLoading = false;
        _isRefreshing = false;
        _errorMessage = _messageForError(error);
      });
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(_errorMessage!)),
      );
    }
  }

  void _selectTag(String tag) {
    Navigator.of(context).pop(tag);
  }

  void _handleSearchChanged(String value) {
    _searchDebounce?.cancel();
    _searchDebounce = Timer(const Duration(milliseconds: 220), () {
      if (!mounted) {
        return;
      }
      setState(() {
        _query = value.trim().toLowerCase();
        _applyFilters();
      });
    });
    setState(() {});
  }

  void _clearSearch() {
    _searchDebounce?.cancel();
    _searchController.clear();
    setState(() {
      _query = '';
      _applyFilters();
    });
  }

  void _applyFilters() {
    final query = _query;
    final letter = _letter;
    final filtered = _allTags.where((tag) {
      final name = tag.name;
      if (query.isNotEmpty && !name.toLowerCase().contains(query)) {
        return false;
      }
      if (letter == '全部') {
        return true;
      }
      return _letterBucket(name) == letter;
    }).toList();

    filtered.sort((a, b) {
      if (_sortMode == _TagSortMode.count) {
        final countCompare = b.sortCount.compareTo(a.sortCount);
        if (countCompare != 0) {
          return countCompare;
        }
      }
      return a.name.toLowerCase().compareTo(b.name.toLowerCase());
    });
    _visibleTags = filtered;
  }

  String _letterBucket(String name) {
    if (name.isEmpty) {
      return '其他';
    }
    final first = name.trimLeft().isEmpty ? '' : name.trimLeft()[0];
    if (first.isEmpty) {
      return '其他';
    }
    final lower = first.toLowerCase();
    final code = lower.codeUnitAt(0);
    if (code >= 97 && code <= 122) {
      return lower.toUpperCase();
    }
    if (code >= 48 && code <= 57) {
      return '0-9';
    }
    return '其他';
  }

  String _messageForError(Object error) {
    final text = error.toString();
    return text.isEmpty ? '标签加载失败' : text;
  }
}

class _SummaryLine extends StatelessWidget {
  const _SummaryLine({
    required this.total,
    required this.visible,
    required this.fetchedAt,
  });

  final int total;
  final int visible;
  final DateTime? fetchedAt;

  @override
  Widget build(BuildContext context) {
    return Text(
      '共 $total 个标签 · 当前显示 $visible 个${_formatFetchedAt()}',
      style: const TextStyle(color: niceMuted, fontSize: 13),
    );
  }

  String _formatFetchedAt() {
    final value = fetchedAt;
    if (value == null) {
      return '';
    }
    String two(int number) => number.toString().padLeft(2, '0');
    return ' · ${two(value.month)}/${two(value.day)} ${two(value.hour)}:${two(value.minute)}';
  }
}

class _LetterStrip extends StatelessWidget {
  const _LetterStrip({
    required this.letters,
    required this.selected,
    required this.onSelected,
  });

  final List<String> letters;
  final String selected;
  final ValueChanged<String> onSelected;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      height: 38,
      child: ListView.separated(
        scrollDirection: Axis.horizontal,
        itemCount: letters.length,
        separatorBuilder: (_, __) => const SizedBox(width: 6),
        itemBuilder: (context, index) {
          final letter = letters[index];
          final active = letter == selected;
          return ChoiceChip(
            label: Text(letter),
            selected: active,
            showCheckmark: false,
            onSelected: (_) => onSelected(letter),
            labelStyle: TextStyle(
              color: active ? niceBlack : niceText,
              fontSize: 12,
              fontWeight: FontWeight.w700,
            ),
            selectedColor: niceAmber,
            backgroundColor: Colors.white.withValues(alpha: 0.07),
            side: BorderSide(color: Colors.white.withValues(alpha: 0.10)),
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(8),
            ),
          );
        },
      ),
    );
  }
}

class _SortButton extends StatelessWidget {
  const _SortButton({
    required this.mode,
    required this.onChanged,
  });

  final _TagSortMode mode;
  final ValueChanged<_TagSortMode> onChanged;

  @override
  Widget build(BuildContext context) {
    return PopupMenuButton<_TagSortMode>(
      tooltip: '排序',
      initialValue: mode,
      onSelected: onChanged,
      itemBuilder: (context) {
        return const [
          PopupMenuItem(
            value: _TagSortMode.count,
            child: Text('按图集数排序'),
          ),
          PopupMenuItem(
            value: _TagSortMode.alphabet,
            child: Text('按字母排序'),
          ),
        ];
      },
      child: Material(
        color: Colors.white.withValues(alpha: 0.07),
        borderRadius: BorderRadius.circular(8),
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 9),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(
                mode == _TagSortMode.count ? '图集数' : '字母',
                style: const TextStyle(
                  color: niceText,
                  fontSize: 12,
                  fontWeight: FontWeight.w700,
                ),
              ),
              const SizedBox(width: 4),
              const Icon(Icons.arrow_drop_down_rounded, color: niceMuted),
            ],
          ),
        ),
      ),
    );
  }
}

class _ErrorView extends StatelessWidget {
  const _ErrorView({
    required this.message,
    required this.onRetry,
  });

  final String message;
  final VoidCallback onRetry;

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 28),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(
              message,
              textAlign: TextAlign.center,
              style: const TextStyle(color: niceMuted, fontSize: 13),
            ),
            const SizedBox(height: 14),
            IconButton.filled(
              onPressed: onRetry,
              icon: const Icon(Icons.refresh_rounded),
              style: IconButton.styleFrom(
                backgroundColor: Colors.white.withValues(alpha: 0.10),
                foregroundColor: niceText,
              ),
            ),
          ],
        ),
      ),
    );
  }
}
