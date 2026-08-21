import 'dart:async';
import 'package:flutter/scheduler.dart';
import 'package:bluebubbles/helpers/helpers.dart';
import 'package:flutter/material.dart';
import 'package:get/get.dart';

/// [GetxController] with support for widget update callbacks
class StatefulController extends GetxController {
  final Map<Object, List<Function>> updateWidgetFunctions = {};

  void updateWidgets<T>(Object? arg) {
    updateWidgetFunctions[T]?.forEach((e) => e.call(arg));
  }
}

/// [StatefulWidget] with a built-in [GetxController]
abstract class CustomStateful<T extends StatefulController> extends StatefulWidget {
  const CustomStateful({super.key, required this.parentController});

  final T parentController;
}

/// [State] with controller lifecycle management and a built-in [GetxController]
abstract class CustomState<T extends CustomStateful, R, S extends StatefulController> extends State<T>
    with ThemeHelpers {
  @protected

  /// Convenience getter for the [GetxController]
  S get controller => widget.parentController as S;

  @protected
  String? _tag;

  /// Set tag of associated [GetxController] if needed
  set tag(String t) => _tag = t;

  @protected
  bool _forceDelete = true;

  /// Set forceDelete false if needed
  set forceDelete(bool fd) => _forceDelete = fd;

  @override
  @mustCallSuper
  void initState() {
    super.initState();
    widget.parentController.updateWidgetFunctions[T] ??= [];
    widget.parentController.updateWidgetFunctions[T]!.add(updateWidget);
  }

  @override

  /// Force delete the [GetxController] when the page has disposed (unless we
  /// don't want to)
  void dispose() {
    widget.parentController.updateWidgetFunctions[T]?.remove(updateWidget);
    if (_forceDelete) Get.delete<S>(tag: _tag);
    super.dispose();
  }

  @protected
  @mustCallSuper
  @optionalTypeArgs

  /// Override this method to update the widget easily
  /// ```
  /// @override
  /// void updateWidget(int newVal) {
  ///   controller.currentPage = newVal;
  ///   super.updateWidget(newVal);
  /// }
  /// ```
  void updateWidget(R newVal) {
    setState(() {});
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// OpenBubbles compatibility shim.
//
// Upstream BlueBubbles removed OptimizedState during the state-management
// rewrite, but ~20 fork-only pages (rustpush setup, Apple passwords, FaceTime,
// profile/poster, polls, FindMy) still extend it. Kept verbatim from the fork so
// those pages keep their frame-aware setState. Migrate them to plain
// `State<T> with ThemeHelpers` when convenient, then delete this.
// ─────────────────────────────────────────────────────────────────────────────

/// Used for cases where we don't need a specific [GetxController], the main
/// benefit of this class is to provide an optimized [setState] function to
/// minimize lag and jank.
abstract class OptimizedState<T extends StatefulWidget> extends State<T> with ThemeHelpers {
  final animCompleted = Completer<void>();

  @override
  @mustCallSuper
  void initState() {
    super.initState();

    WidgetsBinding.instance.addPostFrameCallback((timeStamp) {
      if (mounted && ModalRoute.of(context)?.animation != null) {
        if (ModalRoute.of(context)?.animation?.status != AnimationStatus.completed) {
          late final AnimationStatusListener listener;
          listener = (AnimationStatus status) {
            if (status == AnimationStatus.completed) {
              animCompleted.complete();
              ModalRoute.of(context)?.animation?.removeStatusListener(listener);
            }
          };
          ModalRoute.of(context)?.animation?.addStatusListener(listener);
        } else {
          animCompleted.complete();
        }
      } else {
        animCompleted.complete();
      }
    });
  }

  @override
  void setState(VoidCallback fn) {
    _optimizedUpdate(() {
      super.setState(fn);
    });
  }

  void updateObx(VoidCallback fn) {
    _optimizedUpdate(fn);
  }

  void _optimizedUpdate(VoidCallback fn) {
    if (!mounted) return;

    void checkFrame() {
      // if there's a current frame,
      if (SchedulerBinding.instance.schedulerPhase != SchedulerPhase.idle) {
        // wait for the end of that frame.
        SchedulerBinding.instance.endOfFrame.then((_) {
          if (mounted) fn.call();
        });
      } else {
        if (mounted) fn.call();
      }
    }

    if (animCompleted.isCompleted) {
      checkFrame();
    } else {
      animCompleted.future.then((_) {
        checkFrame();
      });
    }
  }
}
