// Copyright 2015 The Chromium Authors. All rights reserved.
// Use of this source code is governed by a BSD-style license that can be
// found in the LICENSE file.

import 'dart:developer' as developer;
import 'dart:ui' as ui show window;
import 'dart:ui' show AppLifecycleState, Locale;

import 'package:flutter/gestures.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/scheduler.dart';
import 'package:flutter/services.dart';

import 'app.dart';
import 'framework.dart';

export 'dart:ui' show AppLifecycleState, Locale;

/// Interface for classes that register with the Widgets layer binding.
///
/// See [WidgetsBinding.addObserver] and [WidgetsBinding.removeObserver].
abstract class WidgetsBindingObserver {
  /// Called when the system tells the app to pop the current route.
  /// For example, on Android, this is called when the user presses
  /// the back button.
  ///
  /// Observers are notified in registration order until one returns
  /// true. If none return true, the application quits.
  ///
  /// Observers are expected to return true if they were able to
  /// handle the notification, for example by closing an active dialog
  /// box, and false otherwise. The [WidgetsApp] widget uses this
  /// mechanism to notify the [Navigator] widget that it should pop
  /// its current route if possible.
  bool didPopRoute() => false;

  /// Called when the application's dimensions change. For example,
  /// when a phone is rotated.
  void didChangeMetrics() { }

  /// Called when the system tells the app that the user's locale has
  /// changed. For example, if the user changes the system language
  /// settings.
  void didChangeLocale(Locale locale) { }

  /// Called when the system puts the app in the background or returns
  /// the app to the foreground.
  void didChangeAppLifecycleState(AppLifecycleState state) { }
}

/// The glue between the widgets layer and the Flutter engine.
abstract class WidgetsBinding extends BindingBase implements GestureBinding, RendererBinding {
  @override
  void initInstances() {
    super.initInstances();
    _instance = this;
    buildOwner.onBuildScheduled = _handleBuildScheduled;
    ui.window.onLocaleChanged = handleLocaleChanged;
    ui.window.onPopRoute = handlePopRoute;
    ui.window.onAppLifecycleStateChanged = handleAppLifecycleStateChanged;
  }

  /// The current [WidgetsBinding], if one has been created.
  ///
  /// If you need the binding to be constructed before calling [runApp],
  /// you can ensure a Widget binding has been constructed by calling the
  /// `WidgetsFlutterBinding.ensureInitialized()` function.
  static WidgetsBinding get instance => _instance;
  static WidgetsBinding _instance;

  @override
  void initServiceExtensions() {
    super.initServiceExtensions();

    registerSignalServiceExtension(
      name: 'debugDumpApp',
      callback: debugDumpApp
    );

    registerBoolServiceExtension(
      name: 'showPerformanceOverlay',
      getter: () => WidgetsApp.showPerformanceOverlayOverride,
      setter: (bool value) {
        if (WidgetsApp.showPerformanceOverlayOverride == value)
          return;
        WidgetsApp.showPerformanceOverlayOverride = value;
        buildOwner.reassemble(renderViewElement);
      }
    );
  }

  /// The [BuildOwner] in charge of executing the build pipeline for the
  /// widget tree rooted at this binding.
  BuildOwner get buildOwner => _buildOwner;
  final BuildOwner _buildOwner = new BuildOwner();

  final List<WidgetsBindingObserver> _observers = <WidgetsBindingObserver>[];

  /// Registers the given object as a binding observer. Binding
  /// observers are notified when various application events occur,
  /// for example when the system locale changes. Generally, one
  /// widget in the widget tree registers itself as a binding
  /// observer, and converts the system state into inherited widgets.
  ///
  /// For example, the [WidgetsApp] widget registers as a binding
  /// observer and passes the screen size to a [MediaQuery] widget
  /// each time it is built, which enables other widgets to use the
  /// [MediaQuery.of] static method and (implicitly) the
  /// [InheritedWidget] mechanism to be notified whenever the screen
  /// size changes (e.g. whenever the screen rotates).
  void addObserver(WidgetsBindingObserver observer) => _observers.add(observer);

  /// Unregisters the given observer. This should be used sparingly as
  /// it is relatively expensive (O(N) in the number of registered
  /// observers).
  bool removeObserver(WidgetsBindingObserver observer) => _observers.remove(observer);

  /// Called when the system metrics change.
  ///
  /// Notifies all the observers using
  /// [WidgetsBindingObserver.didChangeMetrics].
  ///
  /// See [ui.window.onMetricsChanged].
  @override
  void handleMetricsChanged() {
    super.handleMetricsChanged();
    for (WidgetsBindingObserver observer in _observers)
      observer.didChangeMetrics();
  }

  /// Called when the system locale changes.
  ///
  /// Calls [dispatchLocaleChanged] to notify the binding observers.
  ///
  /// See [ui.window.onLocaleChanged].
  void handleLocaleChanged() {
    dispatchLocaleChanged(ui.window.locale);
  }

  /// Notify all the observers that the locale has changed (using
  /// [WidgetsBindingObserver.didChangeLocale]), giving them the
  /// `locale` argument.
  void dispatchLocaleChanged(Locale locale) {
    for (WidgetsBindingObserver observer in _observers)
      observer.didChangeLocale(locale);
  }

  /// Called when the system pops the current route.
  ///
  /// This first notifies the binding observers (using
  /// [WidgetsBindingObserver.didPopRoute]), in registration order,
  /// until one returns true, meaning that it was able to handle the
  /// request (e.g. by closing a dialog box). If none return true,
  /// then the application is shut down.
  ///
  /// [WidgetsApp] uses this in conjunction with a [Navigator] to
  /// cause the back button to close dialog boxes, return from modal
  /// pages, and so forth.
  ///
  /// See [ui.window.onPopRoute].
  void handlePopRoute() {
    for (WidgetsBindingObserver observer in _observers) {
      if (observer.didPopRoute())
        return;
    }
    activity.finishCurrentActivity();
  }

  /// Called when the application lifecycle state changes.
  ///
  /// Notifies all the observers using
  /// [WidgetsBindingObserver.didChangeAppLifecycleState].
  ///
  /// See [ui.window.onAppLifecycleStateChanged].
  void handleAppLifecycleStateChanged(AppLifecycleState state) {
    for (WidgetsBindingObserver observer in _observers)
      observer.didChangeAppLifecycleState(state);
  }

  bool _needToReportFirstFrame = true;
  bool _thisFrameWasUseful = true;

  /// Tell the framework that the frame we are currently building
  /// should not be considered to be a useful first frame.
  ///
  /// This is used by [WidgetsApp] to report the first frame.
  //
  // TODO(ianh): This method should only be available in debug and profile modes.
  void preventThisFrameFromBeingReportedAsFirstFrame() {
    _thisFrameWasUseful = false;
  }

  void _handleBuildScheduled() {
    // If we're in the process of building dirty elements, we're know that any
    // builds that are scheduled will be run this frame, which means we don't
    // need to schedule another frame.
    if (_buildingDirtyElements)
      return;
    scheduleFrame();
  }

  bool _buildingDirtyElements = false;

  /// Pump the build and rendering pipeline to generate a frame.
  ///
  /// This method is called by [handleBeginFrame], which itself is called
  /// automatically by the engine when when it is time to lay out and paint a
  /// frame.
  ///
  /// Each frame consists of the following phases:
  ///
  /// 1. The animation phase: The [handleBeginFrame] method, which is registered
  /// with [ui.window.onBeginFrame], invokes all the transient frame callbacks
  /// registered with [scheduleFrameCallback] and [addFrameCallback], in
  /// registration order. This includes all the [Ticker] instances that are
  /// driving [AnimationController] objects, which means all of the active
  /// [Animation] objects tick at this point.
  ///
  /// [handleBeginFrame] then invokes all the persistent frame callbacks, of which
  /// the most notable is this method, [beginFrame], which proceeds as follows:
  ///
  /// 2. The build phase: All the dirty [Element]s in the widget tree are
  /// rebuilt (see [State.build]). See [State.setState] for further details on
  /// marking a widget dirty for building. See [BuildOwner] for more information
  /// on this step.
  ///
  /// 3. The layout phase: All the dirty [RenderObject]s in the system are laid
  /// out (see [RenderObject.performLayout]). See [RenderObject.markNeedsLayout]
  /// for further details on marking an object dirty for layout.
  ///
  /// 4. The compositing bits phase: The compositing bits on any dirty
  /// [RenderObject] objects are updated. See
  /// [RenderObject.markNeedsCompositingBitsUpdate].
  ///
  /// 5. The paint phase: All the dirty [RenderObject]s in the system are
  /// repainted (see [RenderObject.paint]). This generates the [Layer] tree. See
  /// [RenderObject.markNeedsPaint] for further details on marking an object
  /// dirty for paint.
  ///
  /// 6. The compositing phase: The layer tree is turned into a [ui.Scene] and
  /// sent to the GPU.
  ///
  /// 7. The semantics phase: All the dirty [RenderObject]s in the system have
  /// their semantics updated (see [RenderObject.semanticAnnotator]). This
  /// generates the [SemanticsNode] tree. See
  /// [RenderObject.markNeedsSemanticsUpdate] for further details on marking an
  /// object dirty for semantics.
  ///
  /// For more details on steps 3-7, see [PipelineOwner].
  ///
  /// 8. The finalization phase in the widgets layer: The widgets tree is
  /// finalized. This causes [State.dispose] to be invoked on any objects that
  /// were removed from the widgets tree this frame. See
  /// [BuildOwner.finalizeTree] for more details.
  ///
  /// 9. The finalization phase in the scheduler layer: After [beginFrame]
  /// returns, [handleBeginFrame] then invokes post-frame callbacks (registered
  /// with [addPostFrameCallback].
  //
  // When editing the above, also update rendering/binding.dart's copy.
  @override
  void beginFrame() {
    assert(!_buildingDirtyElements);
    _buildingDirtyElements = true;
    buildOwner.buildDirtyElements();
    _buildingDirtyElements = false;
    super.beginFrame();
    buildOwner.finalizeTree();
    // TODO(ianh): Following code should not be included in release mode, only profile and debug modes.
    // See https://github.com/dart-lang/sdk/issues/27192
    if (_needToReportFirstFrame) {
      if (_thisFrameWasUseful) {
        developer.Timeline.instantSync('Widgets completed first useful frame');
        developer.postEvent('Flutter.FirstFrame', <String, dynamic>{});
        _needToReportFirstFrame = false;
      } else {
        _thisFrameWasUseful = true;
      }
    }
  }

  /// The [Element] that is at the root of the hierarchy (and which wraps the
  /// [RenderView] object at the root of the rendering hierarchy).
  ///
  /// This is initialized the first time [runApp] is called.
  Element get renderViewElement => _renderViewElement;
  Element _renderViewElement;
  void _runApp(Widget app) {
    _renderViewElement = new RenderObjectToWidgetAdapter<RenderBox>(
      container: renderView,
      debugShortDescription: '[root]',
      child: app
    ).attachToRenderTree(buildOwner, renderViewElement);
    beginFrame();
  }

  @override
  void reassembleApplication() {
    _needToReportFirstFrame = true;
    preventThisFrameFromBeingReportedAsFirstFrame();
    buildOwner.reassemble(renderViewElement);
    super.reassembleApplication();
  }
}

/// Inflate the given widget and attach it to the screen.
///
/// Initializes the binding using [WidgetsFlutterBinding] if necessary.
void runApp(Widget app) {
  WidgetsFlutterBinding.ensureInitialized()._runApp(app);
}

/// Print a string representation of the currently running app.
void debugDumpApp() {
  assert(WidgetsBinding.instance != null);
  assert(WidgetsBinding.instance.renderViewElement != null);
  String mode = 'RELEASE MODE';
  assert(() { mode = 'CHECKED MODE'; return true; });
  debugPrint('${WidgetsBinding.instance.runtimeType} - $mode');
  debugPrint(WidgetsBinding.instance.renderViewElement.toStringDeep());
}

/// A bridge from a [RenderObject] to an [Element] tree.
///
/// The given container is the [RenderObject] that the [Element] tree should be
/// inserted into. It must be a [RenderObject] that implements the
/// [RenderObjectWithChildMixin] protocol. The type argument `T` is the kind of
/// [RenderObject] that the container expects as its child.
///
/// Used by [runApp] to bootstrap applications.
class RenderObjectToWidgetAdapter<T extends RenderObject> extends RenderObjectWidget {
  /// Creates a bridge from a [RenderObject] to an [Element] tree.
  ///
  /// Used by [WidgetsBinding] to attach the root widget to the [RenderView].
  RenderObjectToWidgetAdapter({
    this.child,
    RenderObjectWithChildMixin<T> container,
    this.debugShortDescription
  }) : container = container, super(key: new GlobalObjectKey(container));

  /// The widget below this widget in the tree.
  final Widget child;

  /// The [RenderObject] that is the parent of the [Element] created by this widget.
  final RenderObjectWithChildMixin<T> container;

  /// A short description of this widget used by debugging aids.
  final String debugShortDescription;

  @override
  RenderObjectToWidgetElement<T> createElement() => new RenderObjectToWidgetElement<T>(this);

  @override
  RenderObjectWithChildMixin<T> createRenderObject(BuildContext context) => container;

  @override
  void updateRenderObject(BuildContext context, RenderObject renderObject) { }

  /// Inflate this widget and actually set the resulting [RenderObject] as the
  /// child of [container].
  ///
  /// If `element` is null, this function will create a new element. Otherwise,
  /// the given element will be updated with this widget.
  ///
  /// Used by [runApp] to bootstrap applications.
  RenderObjectToWidgetElement<T> attachToRenderTree(BuildOwner owner, [RenderObjectToWidgetElement<T> element]) {
    owner.lockState(() {
      if (element == null) {
        element = createElement();
        element.assignOwner(owner);
        element.mount(null, null);
      } else {
        element.update(this);
      }
    }, building: true);
    return element;
  }

  @override
  String toStringShort() => debugShortDescription ?? super.toStringShort();
}

/// A [RootRenderObjectElement] that is hosted by a [RenderObject].
///
/// This element class is the instantiation of a [RenderObjectToWidgetAdapter]
/// widget. It can be used only as the root of an [Element] tree (it cannot be
/// mounted into another [Element]; it's parent must be null).
///
/// In typical usage, it will be instantiated for a [RenderObjectToWidgetAdapter]
/// whose container is the [RenderView] that connects to the Flutter engine. In
/// this usage, it is normally instantiated by the bootstrapping logic in the
/// [WidgetsFlutterBinding] singleton created by [runApp].
class RenderObjectToWidgetElement<T extends RenderObject> extends RootRenderObjectElement {
  /// Creates an element that is hosted by a [RenderObject].
  ///
  /// The [RenderObject] created by this element is not automatically set as a
  /// child of the hosting [RenderObject]. To actually attach this element to
  /// the render tree, call [RenderObjectToWidgetAdapter.attachToRenderTree].
  RenderObjectToWidgetElement(RenderObjectToWidgetAdapter<T> widget) : super(widget);

  @override
  RenderObjectToWidgetAdapter<T> get widget => super.widget;

  Element _child;

  static const Object _rootChildSlot = const Object();

  @override
  void visitChildren(ElementVisitor visitor) {
    if (_child != null)
      visitor(_child);
  }

  @override
  void mount(Element parent, dynamic newSlot) {
    assert(parent == null);
    super.mount(parent, newSlot);
    _rebuild();
  }

  @override
  void update(RenderObjectToWidgetAdapter<T> newWidget) {
    super.update(newWidget);
    assert(widget == newWidget);
    _rebuild();
  }

  void _rebuild() {
    try {
      _child = updateChild(_child, widget.child, _rootChildSlot);
      assert(_child != null);
    } catch (exception, stack) {
      FlutterError.reportError(new FlutterErrorDetails(
        exception: exception,
        stack: stack,
        library: 'widgets library',
        context: 'attaching to the render tree'
      ));
      Widget error = new ErrorWidget(exception);
      _child = updateChild(null, error, _rootChildSlot);
    }
  }

  @override
  RenderObjectWithChildMixin<T> get renderObject => super.renderObject;

  @override
  void insertChildRenderObject(RenderObject child, dynamic slot) {
    assert(slot == _rootChildSlot);
    renderObject.child = child;
  }

  @override
  void moveChildRenderObject(RenderObject child, dynamic slot) {
    assert(false);
  }

  @override
  void removeChildRenderObject(RenderObject child) {
    assert(renderObject.child == child);
    renderObject.child = null;
  }
}

/// A concrete binding for applications based on the Widgets framework.
/// This is the glue that binds the framework to the Flutter engine.
class WidgetsFlutterBinding extends BindingBase with SchedulerBinding, GestureBinding, ServicesBinding, RendererBinding, WidgetsBinding {

  /// Returns an instance of the [WidgetsBinding], creating and
  /// initializing it if necessary. If one is created, it will be a
  /// [WidgetsFlutterBinding]. If one was previously initialized, then
  /// it will at least implement [WidgetsBinding].
  ///
  /// You only need to call this method if you need the binding to be
  /// initialized before calling [runApp].
  ///
  /// In the `flutter_test` framework, [testWidgets] initializes the
  /// binding instance to a [TestWidgetsFlutterBinding], not a
  /// [WidgetsFlutterBinding].
  static WidgetsBinding ensureInitialized() {
    if (WidgetsBinding.instance == null)
      new WidgetsFlutterBinding();
    return WidgetsBinding.instance;
  }
}
