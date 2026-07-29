import 'package:flutter/material.dart';

import '../design_system/design_system.dart';
import '../utils/responsive_helper.dart';

/// On mobile: [headerSections] and [mobileSlivers] share one [CustomScrollView].
/// On tablet/desktop: [headerSections] stay fixed above [Expanded(desktopBody)].
/// Desktop/wide: content is centered with [Responsive.maxContentWidth].
class HrmResponsiveListLayout extends StatelessWidget {
  const HrmResponsiveListLayout({
    super.key,
    required this.headerSections,
    required this.desktopBody,
    required this.mobileSlivers,
    this.padding,
    this.physics,
    this.fabAware = false,
    this.extendedFab = false,
    this.constrainWidth = true,
  });

  final EdgeInsetsGeometry? padding;
  final List<Widget> headerSections;
  final Widget desktopBody;
  final List<Widget> Function(BuildContext context) mobileSlivers;
  final ScrollPhysics? physics;
  /// Thêm padding dưới/phải cho **danh sách** khi có FAB.
  final bool fabAware;
  final bool extendedFab;
  /// Giới hạn chiều rộng nội dung trên màn rộng (mặc định bật).
  final bool constrainWidth;

  EdgeInsets? _mobilePadding(BuildContext context) {
    if (!Responsive.useUnifiedPageScroll(context)) return null;
    if (padding == null) return null;
    return padding!.resolve(Directionality.of(context));
  }

  List<Widget> _wrapMobileSlivers(BuildContext context) {
    final slivers = mobileSlivers(context);
    if (!fabAware || !Responsive.useUnifiedPageScroll(context)) {
      return slivers;
    }
    return [
      SliverPadding(
        padding: Responsive.fabScrollBottomInset(
          context,
          extendedFab: extendedFab,
        ),
        sliver: SliverMainAxisGroup(slivers: slivers),
      ),
    ];
  }

  Widget _maybeConstrain(BuildContext context, Widget child) {
    if (!constrainWidth || Responsive.isMobile(context)) return child;
    final max = Responsive.maxContentWidth(context);
    if (max == null) return child;
    return Align(
      alignment: Alignment.topCenter,
      child: ConstrainedBox(
        constraints: BoxConstraints(maxWidth: max),
        child: child,
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    if (Responsive.useUnifiedPageScroll(context)) {
      final headers = headerSections
          .map(
            (w) => SliverToBoxAdapter(
              child: SizedBox(width: double.infinity, child: w),
            ),
          )
          .toList();
      final slivers = <Widget>[...headers, ..._wrapMobileSlivers(context)];
      final scroll = CustomScrollView(
        physics: physics ?? const AlwaysScrollableScrollPhysics(),
        slivers: slivers,
      );
      final mobilePad = _mobilePadding(context);
      final padded =
          mobilePad != null ? Padding(padding: mobilePad, child: scroll) : scroll;
      return _maybeConstrain(context, padded);
    }

    final column = Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        ...headerSections,
        Expanded(child: desktopBody),
      ],
    );
    final padded =
        padding != null ? Padding(padding: padding!, child: column) : column;
    return _maybeConstrain(context, padded);
  }
}

/// Mobile tabbed pages: stats/filters scroll away; [TabBar] pins under them.
class HrmMobileNestedTabLayout extends StatelessWidget {
  const HrmMobileNestedTabLayout({
    super.key,
    required this.headerSections,
    required this.tabBar,
    required this.tabBarView,
    this.padding,
    this.fabAware = false,
    this.extendedFab = false,
  });

  final EdgeInsetsGeometry? padding;
  final List<Widget> headerSections;
  final TabBar tabBar;
  final TabBarView tabBarView;
  final bool fabAware;
  final bool extendedFab;

  Widget _fabAwareTabBody(BuildContext context) {
    if (!fabAware || !Responsive.useUnifiedPageScroll(context)) {
      return tabBarView;
    }
    return Padding(
      padding: Responsive.fabScrollBottomInset(
        context,
        extendedFab: extendedFab,
      ),
      child: tabBarView,
    );
  }

  @override
  Widget build(BuildContext context) {
    if (!Responsive.useUnifiedPageScroll(context)) {
      final column = Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          ...headerSections,
          tabBar,
          Expanded(child: tabBarView),
        ],
      );
      if (padding != null) {
        return Padding(padding: padding!, child: column);
      }
      return column;
    }

    final nested = NestedScrollView(
      headerSliverBuilder: (context, innerBoxIsScrolled) => [
        ...headerSections.map(
          (w) => SliverToBoxAdapter(
            child: SizedBox(width: double.infinity, child: w),
          ),
        ),
        SliverPersistentHeader(
          pinned: true,
          delegate: _SliverTabBarDelegate(tabBar: tabBar),
        ),
      ],
      body: _fabAwareTabBody(context),
    );
    if (padding != null) {
      return Padding(padding: padding!, child: nested);
    }
    return nested;
  }
}

class _SliverTabBarDelegate extends SliverPersistentHeaderDelegate {
  _SliverTabBarDelegate({required this.tabBar});

  final TabBar tabBar;

  @override
  double get minExtent => tabBar.preferredSize.height;

  @override
  double get maxExtent => tabBar.preferredSize.height;

  @override
  Widget build(
      BuildContext context, double shrinkOffset, bool overlapsContent) {
    return Material(
      color: Colors.white,
      elevation: overlapsContent ? 1 : 0,
      child: tabBar,
    );
  }

  @override
  bool shouldRebuild(covariant _SliverTabBarDelegate oldDelegate) =>
      tabBar != oldDelegate.tabBar;
}

/// Helpers for building mobile sliver sections.
class HrmScrollSlivers {
  HrmScrollSlivers._();

  static Widget fillRemaining({
    required Widget child,
    bool hasScrollBody = false,
  }) {
    return SliverFillRemaining(
      hasScrollBody: hasScrollBody,
      child: child,
    );
  }

  static Widget listBuilder({
    required int itemCount,
    required Widget? Function(BuildContext context, int index) itemBuilder,
    EdgeInsetsGeometry? padding,
  }) {
    return SliverPadding(
      padding: padding ?? EdgeInsets.zero,
      sliver: SliverList(
        delegate: SliverChildBuilderDelegate(
          itemBuilder,
          childCount: itemCount,
        ),
      ),
    );
  }

  static Widget childList({
    required List<Widget> children,
    EdgeInsetsGeometry? padding,
  }) {
    return SliverPadding(
      padding: padding ?? EdgeInsets.zero,
      sliver: SliverList(
        delegate: SliverChildListDelegate(children),
      ),
    );
  }

  static Widget toBox(Widget child) => SliverToBoxAdapter(child: child);

  static Widget nestedTabList({
    required Widget child,
  }) {
    return Builder(
      builder: (context) {
        return CustomScrollView(
          primary: false,
          physics: const AlwaysScrollableScrollPhysics(),
          slivers: [
            SliverOverlapInjector(
              handle: NestedScrollView.sliverOverlapAbsorberHandleFor(context),
            ),
            SliverToBoxAdapter(child: child),
          ],
        );
      },
    );
  }

  static List<Widget> fromListViewBuilder({
    required int itemCount,
    required IndexedWidgetBuilder itemBuilder,
    EdgeInsetsGeometry? padding,
  }) {
    return [
      listBuilder(
        itemCount: itemCount,
        itemBuilder: itemBuilder,
        padding: padding,
      ),
    ];
  }
}

/// Mobile: gradient/header block scrolls with body. Desktop: header fixed on top.
class HrmResponsivePageBody extends StatelessWidget {
  const HrmResponsivePageBody({
    super.key,
    required this.header,
    required this.body,
    this.belowHeader = const [],
  });

  final Widget header;
  final List<Widget> belowHeader;
  final Widget body;

  @override
  Widget build(BuildContext context) {
    if (Responsive.useUnifiedPageScroll(context)) {
      return CustomScrollView(
        physics: const AlwaysScrollableScrollPhysics(),
        slivers: [
          SliverToBoxAdapter(child: header),
          for (final w in belowHeader) SliverToBoxAdapter(child: w),
          SliverFillRemaining(
            hasScrollBody: true,
            child: body,
          ),
        ],
      );
    }
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        header,
        ...belowHeader,
        Expanded(child: body),
      ],
    );
  }
}
