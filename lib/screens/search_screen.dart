import 'dart:async';

import 'package:flutter/material.dart';

import '../data/post_repository.dart';
import '../data/profile_repository.dart';
import '../models/post.dart';
import '../models/user_profile.dart';
import '../theme/app_colors.dart';
import '../theme/app_text_styles.dart';
import '../theme/app_theme.dart';
import '../utils/format.dart';
import '../widgets/avatar.dart';
import '../widgets/verified_badge.dart';
import 'post_detail_screen.dart';

/// Explore / search screen backed entirely by the database. A debounced query
/// searches People (profiles) and Posts (content) via the FEAT-001 search
/// RPCs. The idle state shows suggested people to follow. Handles
/// loading / empty / no-results / error states. No fabricated trends.
class SearchScreen extends StatefulWidget {
  const SearchScreen({super.key});

  @override
  State<SearchScreen> createState() => _SearchScreenState();
}

enum _SearchState { idle, loading, results, empty, error }

class _SearchScreenState extends State<SearchScreen> {
  final TextEditingController _controller = TextEditingController();
  Timer? _debounce;

  _SearchState _state = _SearchState.idle;
  String _query = '';
  int _requestSeq = 0;

  List<UserProfile> _people = const <UserProfile>[];
  List<Post> _posts = const <Post>[];
  List<UserProfile> _suggested = const <UserProfile>[];

  @override
  void initState() {
    super.initState();
    _controller.addListener(_onChanged);
    _loadSuggested();
  }

  @override
  void dispose() {
    _debounce?.cancel();
    _controller.dispose();
    super.dispose();
  }

  Future<void> _loadSuggested() async {
    final people = await ProfileRepository.instance.suggestedProfiles();
    if (!mounted) return;
    setState(() => _suggested = people);
  }

  void _onChanged() {
    final text = _controller.text.trim();
    _debounce?.cancel();
    if (text.isEmpty) {
      setState(() {
        _query = '';
        _state = _SearchState.idle;
        _people = const <UserProfile>[];
        _posts = const <Post>[];
      });
      return;
    }
    _debounce = Timer(const Duration(milliseconds: 320), () => _run(text));
  }

  Future<void> _run(String query) async {
    final seq = ++_requestSeq;
    setState(() {
      _query = query;
      _state = _SearchState.loading;
    });
    try {
      final results = await Future.wait(<Future<Object>>[
        ProfileRepository.instance.searchProfiles(query),
        PostRepository.instance.searchPosts(query),
      ]);
      if (!mounted || seq != _requestSeq) return;
      final people = results[0] as List<UserProfile>;
      final posts = results[1] as List<Post>;
      setState(() {
        _people = people;
        _posts = posts;
        _state = (people.isEmpty && posts.isEmpty)
            ? _SearchState.empty
            : _SearchState.results;
      });
    } catch (_) {
      if (!mounted || seq != _requestSeq) return;
      setState(() => _state = _SearchState.error);
    }
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
          decoration: InputDecoration(
            hintText: 'Search Oneleven',
            prefixIcon:
                const Icon(Icons.search, color: AppColors.secondaryText),
            suffixIcon: _controller.text.isEmpty
                ? null
                : IconButton(
                    icon: const Icon(Icons.close,
                        color: AppColors.secondaryText),
                    onPressed: _controller.clear,
                  ),
            isDense: true,
            contentPadding: const EdgeInsets.symmetric(vertical: 8),
          ),
        ),
      ),
      body: _body(),
    );
  }

  Widget _body() {
    switch (_state) {
      case _SearchState.idle:
        return _IdleSuggestions(people: _suggested);
      case _SearchState.loading:
        return const Center(
          child: CircularProgressIndicator(color: AppColors.accent),
        );
      case _SearchState.error:
        return _SearchMessage(
          icon: Icons.error_outline,
          title: 'Search failed',
          subtitle: 'Something went wrong. Try again.',
          actionLabel: 'Retry',
          onAction: () => _run(_query),
        );
      case _SearchState.empty:
        return _SearchMessage(
          icon: Icons.search_off,
          title: 'No results for "$_query"',
          subtitle: 'Try searching for someone or a different keyword.',
        );
      case _SearchState.results:
        return _Results(people: _people, posts: _posts);
    }
  }
}

class _IdleSuggestions extends StatelessWidget {
  const _IdleSuggestions({required this.people});

  final List<UserProfile> people;

  @override
  Widget build(BuildContext context) {
    if (people.isEmpty) {
      return Center(
        child: Padding(
          padding: const EdgeInsets.all(32),
          child: Text(
            'Search for people and posts on Oneleven.',
            textAlign: TextAlign.center,
            style: AppTextStyles.handle,
          ),
        ),
      );
    }
    return ListView(
      children: <Widget>[
        Padding(
          padding: const EdgeInsets.fromLTRB(
            AppSpacing.lg,
            AppSpacing.md,
            AppSpacing.lg,
            AppSpacing.sm,
          ),
          child: Text('Suggested for you', style: AppTextStyles.title),
        ),
        for (final person in people) _PersonTile(person: person),
      ],
    );
  }
}

class _Results extends StatelessWidget {
  const _Results({required this.people, required this.posts});

  final List<UserProfile> people;
  final List<Post> posts;

  @override
  Widget build(BuildContext context) {
    return ListView(
      children: <Widget>[
        if (people.isNotEmpty) ...<Widget>[
          _SectionHeader(title: 'People'),
          for (final person in people) _PersonTile(person: person),
        ],
        if (posts.isNotEmpty) ...<Widget>[
          _SectionHeader(title: 'Posts'),
          for (final post in posts) _PostResultTile(post: post),
        ],
      ],
    );
  }
}

class _SectionHeader extends StatelessWidget {
  const _SectionHeader({required this.title});

  final String title;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(
        AppSpacing.lg,
        AppSpacing.md,
        AppSpacing.lg,
        AppSpacing.sm,
      ),
      child: Text(title, style: AppTextStyles.title),
    );
  }
}

class _PersonTile extends StatelessWidget {
  const _PersonTile({required this.person});

  final UserProfile person;

  @override
  Widget build(BuildContext context) {
    return ListTile(
      onTap: () => openAuthorProfile(context, person.id),
      contentPadding: const EdgeInsets.symmetric(
        horizontal: AppSpacing.lg,
        vertical: 2,
      ),
      leading: Avatar(
        url: person.avatarUrl,
        displayName: person.displayName,
        size: 44,
      ),
      title: Row(
        children: <Widget>[
          Flexible(
            child: Text(
              person.displayName,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: AppTextStyles.name,
            ),
          ),
          if (person.verified) ...<Widget>[
            const SizedBox(width: 4),
            VerifiedBadge(kind: person.verificationKind),
          ],
        ],
      ),
      subtitle: Text(person.handle, style: AppTextStyles.handle),
    );
  }
}

class _PostResultTile extends StatelessWidget {
  const _PostResultTile({required this.post});

  final Post post;

  @override
  Widget build(BuildContext context) {
    final author = post.author;
    return ListTile(
      onTap: () => openPostDetail(context, post),
      contentPadding: const EdgeInsets.symmetric(
        horizontal: AppSpacing.lg,
        vertical: 4,
      ),
      leading: Avatar(
        url: author.avatarUrl,
        displayName: author.displayName,
        size: 40,
      ),
      title: Text(
        author.displayName,
        maxLines: 1,
        overflow: TextOverflow.ellipsis,
        style: AppTextStyles.name,
      ),
      subtitle: Text(
        post.content,
        maxLines: 2,
        overflow: TextOverflow.ellipsis,
        style: AppTextStyles.handle,
      ),
      trailing: Text(timeAgo(post.createdAt), style: AppTextStyles.caption),
    );
  }
}

class _SearchMessage extends StatelessWidget {
  const _SearchMessage({
    required this.icon,
    required this.title,
    required this.subtitle,
    this.actionLabel,
    this.onAction,
  });

  final IconData icon;
  final String title;
  final String subtitle;
  final String? actionLabel;
  final VoidCallback? onAction;

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(32),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: <Widget>[
            Icon(icon, size: 48, color: AppColors.secondaryText),
            const SizedBox(height: 12),
            Text(title, style: AppTextStyles.title, textAlign: TextAlign.center),
            const SizedBox(height: 6),
            Text(
              subtitle,
              textAlign: TextAlign.center,
              style: AppTextStyles.handle,
            ),
            if (actionLabel != null && onAction != null) ...<Widget>[
              const SizedBox(height: AppSpacing.md),
              OutlinedButton(
                onPressed: onAction,
                child: Text(actionLabel!),
              ),
            ],
          ],
        ),
      ),
    );
  }
}
