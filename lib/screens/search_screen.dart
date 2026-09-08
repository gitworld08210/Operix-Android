import 'package:flutter/material.dart';

import '../theme/app_colors.dart';
import '../theme/app_text_styles.dart';
import '../theme/app_theme.dart';
import '../utils/format.dart';

/// A simple Explore screen: a search field, trending chips, and a list of
/// 'Trends for you' backed by static demo data.
class SearchScreen extends StatefulWidget {
  const SearchScreen({super.key});

  @override
  State<SearchScreen> createState() => _SearchScreenState();
}

class _SearchScreenState extends State<SearchScreen> {
  final TextEditingController _controller = TextEditingController();

  static const List<String> _chips = <String>[
    'For you',
    'Trending',
    'News',
    'Sports',
    'Tech',
    'Entertainment',
  ];

  static const List<_Trend> _trends = <_Trend>[
    _Trend('Technology', '#Flutter', 128400),
    _Trend('Trending', '#DesignSystems', 54200),
    _Trend('Business', 'Open Source', 31900),
    _Trend('Sports', '#CityTransit', 22800),
    _Trend('Only on Oneleven', 'Skeleton screens', 18200),
    _Trend('Photography', 'Golden hour', 9700),
  ];

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        titleSpacing: 16,
        title: TextField(
          controller: _controller,
          textInputAction: TextInputAction.search,
          style: AppTextStyles.body,
          decoration: const InputDecoration(
            hintText: 'Search Oneleven',
            prefixIcon: Icon(Icons.search, color: AppColors.secondaryText),
            isDense: true,
            contentPadding: EdgeInsets.symmetric(vertical: 8),
          ),
        ),
      ),
      body: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          SizedBox(
            height: 52,
            child: ListView.separated(
              scrollDirection: Axis.horizontal,
              padding: const EdgeInsets.symmetric(horizontal: AppSpacing.lg),
              itemCount: _chips.length,
              separatorBuilder: (_, __) => const SizedBox(width: AppSpacing.sm),
              itemBuilder: (context, index) {
                return Center(
                  child: Chip(
                    label: Text(_chips[index]),
                    backgroundColor: AppColors.surface,
                    labelStyle: AppTextStyles.label,
                    side: const BorderSide(color: AppColors.border),
                  ),
                );
              },
            ),
          ),
          const Divider(height: 0.5),
          Padding(
            padding: const EdgeInsets.fromLTRB(
              AppSpacing.lg,
              AppSpacing.md,
              AppSpacing.lg,
              AppSpacing.sm,
            ),
            child: Text('Trends for you', style: AppTextStyles.title),
          ),
          Expanded(
            child: ListView.builder(
              itemCount: _trends.length,
              itemBuilder: (context, index) {
                final trend = _trends[index];
                return ListTile(
                  contentPadding: const EdgeInsets.symmetric(
                    horizontal: AppSpacing.lg,
                    vertical: 2,
                  ),
                  title: Text(trend.title, style: AppTextStyles.name),
                  subtitle: Text(
                    '${trend.category} · ${fmtCount(trend.posts)} posts',
                    style: AppTextStyles.caption,
                  ),
                  trailing: const Icon(
                    Icons.more_horiz,
                    color: AppColors.secondaryText,
                  ),
                  onTap: () {},
                );
              },
            ),
          ),
        ],
      ),
    );
  }
}

class _Trend {
  const _Trend(this.category, this.title, this.posts);

  final String category;
  final String title;
  final int posts;
}
