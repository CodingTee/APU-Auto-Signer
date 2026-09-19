import 'package:flutter/material.dart';
import 'package:mobile_scanner/mobile_scanner.dart';
import 'package:permission_handler/permission_handler.dart';

/// Full-screen QR scanner with a custom overlay (gray gradient outside
/// the scan frame, white corner brackets, animated green scan line).
/// Pops with the decoded 3-digit OTP code on success. Shows a debounced
/// inline error if the scanned value is not exactly 3 digits.
class ScannerScreen extends StatefulWidget {
  const ScannerScreen({super.key});

  @override
  State<ScannerScreen> createState() => _ScannerScreenState();
}

class _ScannerScreenState extends State<ScannerScreen>
    with SingleTickerProviderStateMixin {
  late final MobileScannerController _controller;
  late final AnimationController _scanAnimController;
  bool _hasPermission = false;
  bool _handled = false;
  DateTime? _lastInvalidShown;

  static final _otpRegex = RegExp(r'^\d{3}$');

  @override
  void initState() {
    super.initState();
    _controller = MobileScannerController(
      detectionSpeed: DetectionSpeed.noDuplicates,
      formats: const [BarcodeFormat.qrCode],
    );
    _scanAnimController = AnimationController(
      duration: const Duration(milliseconds: 2200),
      vsync: this,
    )..repeat(reverse: true);
    _ensurePermission();
  }

  @override
  void dispose() {
    _scanAnimController.dispose();
    _controller.dispose();
    super.dispose();
  }

  Future<void> _ensurePermission() async {
    var status = await Permission.camera.status;
    if (!status.isGranted) {
      status = await Permission.camera.request();
    }
    if (!mounted) return;
    if (status.isGranted) {
      setState(() => _hasPermission = true);
      // Explicitly start the camera now that permission is granted;
      // without this MobileScanner shows the exclamation mark overlay
      // until the screen is rebuilt.
      try {
        await _controller.start();
      } catch (_) {
        // best-effort; the widget rebuild on setState will retry.
      }
    } else {
      setState(() => _hasPermission = false);
    }
  }

  void _onDetect(BarcodeCapture capture) {
    if (_handled) return;
    if (capture.barcodes.isEmpty) return;
    final raw = capture.barcodes.first.rawValue;
    if (raw == null || raw.isEmpty) return;
    final code = raw.trim();
    if (!_otpRegex.hasMatch(code)) {
      final now = DateTime.now();
      if (_lastInvalidShown == null ||
          now.difference(_lastInvalidShown!).inSeconds >= 2) {
        _lastInvalidShown = now;
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Invalid code: must be exactly 3 digits'),
            duration: Duration(seconds: 2),
          ),
        );
      }
      return;
    }
    _handled = true;
    Navigator.of(context).pop(code);
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Scan OTP QR')),
      body: _hasPermission ? _buildScanner() : _buildPermissionDenied(),
    );
  }

  Widget _buildScanner() {
    return Stack(
      children: [
        MobileScanner(
          controller: _controller,
          onDetect: _onDetect,
        ),
        _ScannerOverlay(animation: _scanAnimController),
        Positioned(
          left: 0,
          right: 0,
          bottom: 0,
          child: Container(
            padding: const EdgeInsets.all(16),
            color: Colors.black54,
            child: const SafeArea(
              top: false,
              child: Text(
                'Point the camera at the 3-digit code QR',
                textAlign: TextAlign.center,
                style: TextStyle(color: Colors.white, fontSize: 14),
              ),
            ),
          ),
        ),
      ],
    );
  }

  Widget _buildPermissionDenied() {
    return Container(
      color: Colors.black,
      child: Center(
        child: Padding(
          padding: const EdgeInsets.all(32),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              const Icon(Icons.no_photography,
                  size: 64, color: Colors.white70),
              const SizedBox(height: 16),
              const Text(
                'Camera permission required',
                style: TextStyle(color: Colors.white, fontSize: 18),
              ),
              const SizedBox(height: 8),
              const Text(
                'Please grant camera access to scan the OTP QR code.',
                textAlign: TextAlign.center,
                style: TextStyle(color: Colors.white70, fontSize: 14),
              ),
              const SizedBox(height: 24),
              FilledButton.icon(
                icon: const Icon(Icons.lock_open),
                label: const Text('Grant Permission'),
                onPressed: _ensurePermission,
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// Paints the dimmed background, corner brackets, and animated scan line.
class _ScannerOverlay extends StatelessWidget {
  final Animation<double> animation;
  const _ScannerOverlay({required this.animation});

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: animation,
      builder: (context, _) {
        return LayoutBuilder(
          builder: (context, constraints) {
            final scanSize = constraints.maxWidth < constraints.maxHeight
                ? constraints.maxWidth * 0.7
                : constraints.maxHeight * 0.5;
            return CustomPaint(
              painter: _ScannerOverlayPainter(
                animationValue: animation.value,
                scanSize: scanSize,
              ),
              child: const SizedBox.expand(),
            );
          },
        );
      },
    );
  }
}

class _ScannerOverlayPainter extends CustomPainter {
  final double animationValue;
  final double scanSize;
  _ScannerOverlayPainter({
    required this.animationValue,
    required this.scanSize,
  });

  @override
  void paint(Canvas canvas, Size size) {
    final center = Offset(size.width / 2, size.height / 2);
    final scanRect = Rect.fromCenter(
      center: center,
      width: scanSize,
      height: scanSize,
    );

    // 1. Gray gradient overlay outside the scan frame (hole).
    final bgPath = Path()
      ..addRect(Rect.fromLTWH(0, 0, size.width, size.height));
    final hole = Path()
      ..addRRect(
        RRect.fromRectAndRadius(scanRect, const Radius.circular(20)),
      );
    final combined = Path.combine(PathOperation.difference, bgPath, hole);
    final overlayPaint = Paint()
      ..shader = const LinearGradient(
        begin: Alignment.topCenter,
        end: Alignment.bottomCenter,
        colors: [Color(0x99000000), Color(0xCC000000), Color(0x99000000)],
      ).createShader(Rect.fromLTWH(0, 0, size.width, size.height));
    canvas.drawPath(combined, overlayPaint);

    // 2. White corner brackets.
    final cornerPaint = Paint()
      ..color = Colors.white
      ..strokeWidth = 4
      ..strokeCap = StrokeCap.round
      ..style = PaintingStyle.stroke;
    const cornerLength = 28.0;
    final r = scanRect;
    canvas.drawLine(
        r.topLeft, r.topLeft + const Offset(cornerLength, 0), cornerPaint);
    canvas.drawLine(
        r.topLeft, r.topLeft + const Offset(0, cornerLength), cornerPaint);
    canvas.drawLine(r.topRight,
        r.topRight + const Offset(-cornerLength, 0), cornerPaint);
    canvas.drawLine(
        r.topRight, r.topRight + const Offset(0, cornerLength), cornerPaint);
    canvas.drawLine(r.bottomLeft,
        r.bottomLeft + const Offset(cornerLength, 0), cornerPaint);
    canvas.drawLine(r.bottomLeft,
        r.bottomLeft + const Offset(0, -cornerLength), cornerPaint);
    canvas.drawLine(r.bottomRight,
        r.bottomRight + const Offset(-cornerLength, 0), cornerPaint);
    canvas.drawLine(r.bottomRight,
        r.bottomRight + const Offset(0, -cornerLength), cornerPaint);

    // Clip the glow + scan line to the scan frame so they cannot bleed
    // onto the dimmed area outside the hole.
    canvas.save();
    canvas.clipPath(hole);

    // 3. Soft green glow band (background of the scan line).
    final lineY = scanRect.top + scanRect.height * animationValue;
    final glowRect = Rect.fromLTRB(
      scanRect.left + 12,
      lineY - 18,
      scanRect.right - 12,
      lineY + 18,
    );
    final glowPaint = Paint()
      ..shader = const LinearGradient(
        begin: Alignment.centerLeft,
        end: Alignment.centerRight,
        colors: [
          Color(0x0000FF7F),
          Color(0x2200FF7F),
          Color(0x4400FF7F),
          Color(0x2200FF7F),
          Color(0x0000FF7F),
        ],
        stops: [0.0, 0.25, 0.5, 0.75, 1.0],
      ).createShader(glowRect);
    canvas.drawRRect(
      RRect.fromRectAndRadius(glowRect, const Radius.circular(8)),
      glowPaint,
    );

    // 4. Bright horizontal scan line with horizontal gradient (green
    // fades out toward the edges so it looks like a glowing stripe).
    const lineHeight = 4.0;
    final lineRect = Rect.fromLTRB(
      scanRect.left + 12,
      lineY - lineHeight / 2,
      scanRect.right - 12,
      lineY + lineHeight / 2,
    );
    final linePaint = Paint()
      ..shader = const LinearGradient(
        begin: Alignment.centerLeft,
        end: Alignment.centerRight,
        colors: [
          Color(0x0000FF7F),
          Color(0xAA00FF7F),
          Color(0xFF00FF7F),
          Color(0xAA00FF7F),
          Color(0x0000FF7F),
        ],
        stops: [0.0, 0.25, 0.5, 0.75, 1.0],
      ).createShader(lineRect);
    canvas.drawRRect(
      RRect.fromRectAndRadius(lineRect, const Radius.circular(2)),
      linePaint,
    );

    canvas.restore();
  }

  @override
  bool shouldRepaint(_ScannerOverlayPainter oldDelegate) {
    return oldDelegate.animationValue != animationValue ||
        oldDelegate.scanSize != scanSize;
  }
}