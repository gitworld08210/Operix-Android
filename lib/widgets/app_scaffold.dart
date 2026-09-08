import 'package:flutter/material.dart';

import '../data/message_repository.dart';
import '../data/notification_repository.dart';
import '../data/profile_repository.dart';
import '../models/user_profile.dart';
import '../screens/compose_screen.dart';
import '../screens/home_feed_screen.dart';
import '../screens/messages_screen.dart';
import '../screens/notifications_screen.dart';
import '../screens/profile_screen.dart';
import '../screens/search_screen.dart';
import '../theme/app_colors.dart';

/// The app shell: an [IndexedStack] body driven by a bottom [NavigationBar]
/// with Home / Search / Compose / Notifications / Messages. Compose opens a
/// modal route instead of swapping the body. Profile is reachable from the
/// Home top bar avatar.
class AppScaffold extends StatefulWidget {
  const AppScaffold({super.key});

  @override
  State<AppScaffold> createState() => _AppScaffoldState();
}

class _AppScaffoldState extends State<AppScaffold> {
  int _index = 0;

  // Body pages, aligned to nav indices 0,1,3,4 (index 2 is Compose action).
  final List<Widget> _pages = const <Widget>[
    HomeFeedScreen(),
    SearchScreen(),
    SizedBox.shrink(), // placeholder for Compose slot
    NotificationsScreen(),
    MessagesScreen(),
  ];

  void _openCompose() {
    Navigator.of(context).push(
      MaterialPageRoute<void>(
        fullscreenDialog: true,
        builder: (_) => const ComposeScreen(),
      ),
    );
  }

  void _onDestinationSelected(int index) {
    if (index == 2) {
      _openCompose();
      return;
    }
    setState(() => _index = index);
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: IndexedStack(index: _index, children: _pages),
      bottomNavigationBar: DecoratedBox(
        decoration: const BoxDecoration(
          border: Border(
            top: BorderSide(color: AppColors.border, width: 0.5),
          ),
        ),
        // Listen to the notification + message repositories so the unread
        // badges refresh live (e.g. after markNotificationsRead) without
        // needing an unrelated shell rebuild.
        child: AnimatedBuilder(
          animation: Listenable.merge(<Listenable>[
            NotificationRepository.instance,
            MessageRepository.instance,
          ]),
          builder: (context, _) => NavigationBar(
            selectedIndex: _index,
            onDestinationSelected: _onDestinationSelected,
            destinations: <Widget>[
            const NavigationDestination(
              icon: Icon(Icons.home_outlined),
              selectedIcon: Icon(Icons.home),
              label: 'Home',
            ),
            const NavigationDestination(
              icon: Icon(Icons.search),
              selectedIcon: Icon(Icons.search),
              label: 'Search',
            ),
            NavigationDestination(
              icon: Container(
                width: 30,
                height: 30,
                decoration: const BoxDecoration(
                  color: AppColors.accent,
                  shape: BoxShape.circle,
                ),
                child: const Icon(Icons.add, color: AppColors.white, size: 20),
              ),
              label: 'Compose',
            ),
            NavigationDestination(
              icon: _NotifIcon(
                icon: Icons.notifications_none,
                count: NotificationRepository.instance.unreadNotifications,
              ),
              selectedIcon: _NotifIcon(
                icon: Icons.notifications,
                count: NotificationRepository.instance.unreadNotifications,
              ),
              label: 'Notifications',
            ),
            NavigationDestination(
              icon: _NotifIcon(
                icon: Icons.mail_outline,
                count: MessageRepository.instance.unreadMessages,
              ),
              selectedIcon: _NotifIcon(
                icon: Icons.mail,
                count: MessageRepository.instance.unreadMessages,
              ),
              label: 'Messages',
            ),
            ],
          ),
        ),
      ),
    );
  }
}

/// Navigates to the current user's profile. No-op until the current user has
/// loaded (profiles are fetched asynchronously after sign-in).
void openProfile(BuildContext context) {
  final UserProfile? user = ProfileRepository.instance.currentUser;
  if (user == null) return;
  Navigator.of(context).push(
    MaterialPageRoute<void>(
      builder: (_) => ProfileScreen(profile: user),
    ),
  );
}

class _NotifIcon extends StatelessWidget {
  const _NotifIcon({required this.icon, required this.count});

  final IconData icon;
  final int count;

  @override
  Widget build(BuildContext context) {
    if (count <= 0) return Icon(icon);
    return Stack(
      clipBehavior: Clip.none,
      children: <Widget>[
        Icon(icon),
        Positioned(
          top: -4,
          right: -6,
          child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 1),
            constraints: const BoxConstraints(minWidth: 16),
            decoration: const BoxDecoration(
              color: AppColors.accent,
              shape: BoxShape.circle,
            ),
            child: Text(
              count > 9 ? '9+' : '$count',
              textAlign: TextAlign.center,
              style: const TextStyle(
                color: AppColors.white,
                fontSize: 10,
                fontWeight: FontWeight.w700,
              ),
            ),
          ),
        ),
      ],
    );
  }
}
