import 'dart:async';
import 'dart:math';

import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';

class FloatingScroller extends StatefulWidget {
  final ScrollController scrollController;
  final Widget child;
  final EdgeInsetsGeometry padding;

  final Widget thumb;
  final Size thumbSize;
  final bool isAlwaysShown;

  final Duration scrollInterval;

  const FloatingScroller({
    key,
    this.padding = EdgeInsets.zero,
    required this.child,
    required this.scrollController,
    this.thumb = const FloatingScrollerDefaultThumb(),
    this.thumbSize = FloatingScrollerDefaultThumb.size,
    this.isAlwaysShown = false,
    this.scrollInterval = const Duration(milliseconds: 100),
  }) : super(key: key);
  @override
  createState() => FloatingScrollerState();
}

class FloatingScrollerState extends State<FloatingScroller> {
  late final _Debouncer _thumbDebouncer;
  late final _Throttle _scrollThrottle;
  final _stageKey = GlobalKey();

  double _thumbTop = 0;
  bool _isTabVisible = false;
  bool _isThumbDragging = false;

  @override
  void initState() {
    _thumbDebouncer = _Debouncer();
    _scrollThrottle = _Throttle(widget.scrollInterval);
    super.initState();
  }

  @override
  void dispose() {
    _thumbDebouncer.clear();
    _scrollThrottle.dispose();
    super.dispose();
  }

  void _showTab() {
    _thumbDebouncer.clear();
    setState(() {
      _isTabVisible = true;
    });
  }

  void _requestToHideTab(
      [Duration delay = const Duration(milliseconds: 1000)]) {
    _thumbDebouncer.run(() {
      setState(() {
        _isTabVisible = false;
      });
    }, delay);
  }

  bool _onNotification(Notification notification) {
    if (notification is! ScrollNotification) {
      return true;
    }

    if (notification is ScrollStartNotification) {
      _showTab();
    }

    if (notification is ScrollEndNotification) {
      _requestToHideTab(const Duration(milliseconds: 500));
    }

    if (notification is ScrollUpdateNotification) {
      if (!_isThumbDragging) {
        updateThumbPosition(notification.metrics.pixels);
      }
    }
    return false;
  }

  updateThumbPosition(double scrollOffset) {
    final scrollPosition = widget.scrollController.position;
    final scrollRange =
        scrollPosition.maxScrollExtent - scrollPosition.minScrollExtent;
    final renderBox = _stageKey.currentContext!.findRenderObject() as RenderBox;
    final maxThumbTop = renderBox.size.height - widget.thumbSize.height;
    final newThumbTop = maxThumbTop * scrollOffset / scrollRange;
    setState(() {
      _thumbTop = max(0.0, min(newThumbTop, maxThumbTop));
    });
  }

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        return Stack(
          children: [
            NotificationListener(
              onNotification: _onNotification,
              child: widget.child,
            ),
            Container(
              padding: widget.padding,
              child: GestureDetector(
                key: _stageKey,
                behavior: HitTestBehavior.deferToChild,
                dragStartBehavior: DragStartBehavior.down,
                onPanStart: (details) {
                  _isThumbDragging = true;
                },
                onPanUpdate: (details) {
                  if (_isThumbDragging) {
                    final renderBox = _stageKey.currentContext!
                        .findRenderObject() as RenderBox;
                    final maxThumbTop =
                        renderBox.size.height - widget.thumbSize.height;

                    final scrollPosition = widget.scrollController.position;
                    final scrollDimension = scrollPosition.maxScrollExtent -
                        scrollPosition.minScrollExtent;
                    final pos =
                        details.localPosition.dy - widget.thumbSize.height / 2;
                    final scrollOffset = max(
                        0.0,
                        min(
                          scrollPosition.minScrollExtent +
                              pos * scrollDimension / maxThumbTop,
                          scrollPosition.maxScrollExtent,
                        )).roundToDouble();

                    updateThumbPosition(scrollOffset);
                    _scrollThrottle.run(() {
                      widget.scrollController.jumpTo(scrollOffset);
                    });
                  }
                },
                onPanCancel: () {
                  _isThumbDragging = false;
                  _requestToHideTab();
                },
                onPanEnd: (details) {
                  _isThumbDragging = false;
                  _requestToHideTab();
                },
                child: Stack(
                  clipBehavior: Clip.none,
                  children: [
                    Positioned(
                      right: 0,
                      top: _thumbTop,
                      child: _ThumbBox(
                        visible: widget.isAlwaysShown ||
                            _isTabVisible ||
                            _isThumbDragging,
                        thumb: widget.thumb,
                        thumbSize: widget.thumbSize,
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ],
        );
      },
    );
  }
}

class _ThumbBox extends StatelessWidget {
  final bool visible;
  final Widget thumb;
  final Size thumbSize;
  const _ThumbBox({
    key,
    required this.thumb,
    required this.thumbSize,
    required this.visible,
  }) : super(key: key);
  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: thumbSize.width,
      height: thumbSize.height,
      child: Stack(clipBehavior: Clip.none, children: [
        AnimatedPositioned(
          right: visible ? 0 : -thumbSize.width,
          curve: Curves.linear,
          duration: const Duration(milliseconds: 250),
          child: thumb,
        ),
      ]),
    );
  }
}

class FloatingScrollerDefaultThumb extends StatelessWidget {
  static const size = Size(40, 56);
  final Color backgroundColor;
  final Color foregroundColor;
  const FloatingScrollerDefaultThumb({
    key,
    this.foregroundColor = Colors.black,
    this.backgroundColor = const Color(0xffe0e0e0),
  }) : super(key: key);
  @override
  Widget build(BuildContext context) {
    return Container(
      padding: EdgeInsets.only(left: size.width / 4),
      decoration: BoxDecoration(
        color: backgroundColor,
        borderRadius: BorderRadius.only(
          topLeft: Radius.circular(size.height),
          bottomLeft: Radius.circular(size.height),
        ),
      ),
      width: size.width,
      height: size.height,
      child: Icon(Icons.unfold_more, color: foregroundColor),
    );
  }
}

class _Debouncer {
  Timer? _timer;
  _Debouncer();
  run(VoidCallback action, Duration delay) {
    _timer?.cancel();
    _timer = Timer(delay, action);
  }

  clear() {
    _timer?.cancel();
  }
}

class _Throttle {
  late final Timer _timer;
  final Duration interval;
  VoidCallback? _action;

  _Throttle(this.interval) {
    _timer = Timer.periodic(interval, _runner);
  }

  _runner(Timer timer) {
    _action?.call();
    _action = null;
  }

  run(VoidCallback action) {
    _action = action;
  }

  dispose() {
    _timer.cancel();
  }
}
