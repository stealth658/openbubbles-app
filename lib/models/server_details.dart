import 'package:flutter/foundation.dart';

@immutable
class ServerDetails {
  final int macOSVersion;
  final int macOSMinorVersion;
  final String serverVersion;
  final int serverVersionCode;

  const ServerDetails({
    required this.macOSVersion,
    required this.macOSMinorVersion,
    required this.serverVersion,
    required this.serverVersionCode,
  });

  const ServerDetails.empty()
      : macOSVersion = 0,
        macOSMinorVersion = 0,
        serverVersion = "",
        serverVersionCode = 0;
}
