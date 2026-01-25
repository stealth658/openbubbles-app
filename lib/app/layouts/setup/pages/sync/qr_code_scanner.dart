import 'package:bluebubbles/helpers/helpers.dart';
import 'package:bluebubbles/app/wrappers/bb_annotated_region.dart';
import 'package:bluebubbles/app/wrappers/stateful_boilerplate.dart';
import 'package:flutter/material.dart';
import 'package:get/get.dart';
import 'package:mobile_scanner/mobile_scanner.dart';

class QRCodeScanner extends StatefulWidget {
  const QRCodeScanner({super.key});

  @override
  State<QRCodeScanner> createState() => _QRCodeScannerState();
}

class _QRCodeScannerState extends OptimizedState<QRCodeScanner> {
  final GlobalKey qrKey = GlobalKey(debugLabel: 'QR');
  bool scanned = false;

  @override
  Widget build(BuildContext context) {
    return BBAnnotatedRegion(
      child: Scaffold(
        backgroundColor: context.theme.colorScheme.background,
        body: MobileScanner(
          key: qrKey,
          onDetect: (capture) {
            if (!scanned && !isNullOrEmpty(capture.barcodes.first.rawValue)) {
              scanned = true;
              Navigator.of(context).pop(capture.barcodes.first.rawValue);
            }
          },
        ),
      ),
    );
  }
}
