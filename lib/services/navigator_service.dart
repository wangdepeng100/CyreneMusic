import 'package:flutter/widgets.dart';

class NavigatorService {
  static final NavigatorService _instance = NavigatorService._internal();
  factory NavigatorService() => _instance;
  NavigatorService._internal();

  final GlobalKey<NavigatorState> navigatorKey = GlobalKey<NavigatorState>();
}