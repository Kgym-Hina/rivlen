import 'dart:convert';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:mobile_scanner/mobile_scanner.dart';

import '../models/connection_result.dart';
import '../models/gateway_pairing_file.dart';
import '../services/gateway_api.dart';
import '../services/node_red_api.dart';
import '../theme.dart';

class PairGatewayScreen extends StatefulWidget {
  const PairGatewayScreen({super.key});

  @override
  State<PairGatewayScreen> createState() => _PairGatewayScreenState();
}

class _PairGatewayScreenState extends State<PairGatewayScreen> {
  final _scanner = MobileScannerController(
    facing: CameraFacing.back,
    detectionSpeed: DetectionSpeed.noDuplicates,
  );
  final _password = TextEditingController();
  final _deviceName = TextEditingController(text: 'Rivlen 设备');
  GatewayPairingFile? _pairingFile;
  String? _error;
  bool _reading = false;
  bool _pairing = false;
  bool _showPassword = false;

  @override
  void dispose() {
    _scanner.dispose();
    _password.dispose();
    _deviceName.dispose();
    super.dispose();
  }

  Future<void> _readBarcode(BarcodeCapture capture) async {
    if (_reading || _pairingFile != null) return;
    final codes = capture.barcodes
        .map((barcode) => barcode.rawValue)
        .whereType<String>()
        .where((value) => value.isNotEmpty)
        .toList();
    if (codes.isEmpty) return;
    final raw = codes.first;
    await _acceptFile(raw);
  }

  Future<void> _chooseFile() async {
    try {
      final files = await FilePicker.pickFiles(
        type: FileType.custom,
        allowedExtensions: const ['json', 'rivpair'],
      );
      if (files.isEmpty) return;
      final bytes = await files.single.readAsBytes();
      await _acceptFile(utf8.decode(bytes));
    } catch (error) {
      if (!mounted) return;
      setState(() => _error = _message(error));
    }
  }

  Future<void> _acceptFile(String raw) async {
    if (_reading) return;
    setState(() {
      _reading = true;
      _error = null;
    });
    try {
      final pairingFile = GatewayPairingFile.decode(raw);
      await _scanner.stop();
      if (!mounted) return;
      setState(() => _pairingFile = pairingFile);
    } catch (error) {
      if (mounted) setState(() => _error = _message(error));
    } finally {
      if (mounted) setState(() => _reading = false);
    }
  }

  Future<void> _pair() async {
    final file = _pairingFile;
    if (file == null || _password.text.isEmpty) {
      setState(() => _error = '请输入网关配对密码。');
      return;
    }
    FocusScope.of(context).unfocus();
    setState(() {
      _pairing = true;
      _error = null;
    });
    final gatewayApi = GatewayApi();
    final nodeRedApi = NodeRedApi();
    try {
      final connection = await gatewayApi.pair(
        pairingFile: file,
        password: _password.text,
        deviceName: _deviceName.text.trim().isEmpty
            ? 'Rivlen 设备'
            : _deviceName.text.trim(),
      );
      final bundle = await nodeRedApi.getFlows(connection);
      await gatewayApi.dispose();
      await nodeRedApi.dispose();
      if (!mounted) return;
      Navigator.pop(context, ConnectionResult(connection, bundle));
    } catch (error) {
      await gatewayApi.dispose();
      await nodeRedApi.dispose();
      if (mounted) {
        setState(() {
          _pairing = false;
          _error = _message(error);
        });
      }
    }
  }

  String _message(Object error) =>
      error.toString().replaceFirst('Exception: ', '');

  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(
      leading: IconButton(
        onPressed: _pairing ? null : () => Navigator.pop(context),
        icon: const Icon(Icons.arrow_back_rounded),
      ),
      title: const Text('配对网关'),
    ),
    body: SafeArea(
      child: _pairingFile == null ? _scannerView() : _pairingForm(),
    ),
  );

  Widget _scannerView() => Padding(
    padding: const EdgeInsets.fromLTRB(22, 8, 22, 24),
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        const Text(
          '扫描配对二维码',
          style: TextStyle(
            color: RivlenColors.ink,
            fontSize: 24,
            fontWeight: FontWeight.w700,
            letterSpacing: -0.5,
          ),
        ),
        const SizedBox(height: 7),
        Text(
          '也可以导入网关生成的配对文件。',
          style: TextStyle(color: RivlenColors.muted, fontSize: 13),
        ),
        const SizedBox(height: 20),
        Expanded(
          child: ClipRRect(
            borderRadius: BorderRadius.circular(22),
            child: Stack(
              fit: StackFit.expand,
              children: [
                MobileScanner(controller: _scanner, onDetect: _readBarcode),
                IgnorePointer(
                  child: Center(
                    child: Container(
                      width: 232,
                      height: 232,
                      decoration: BoxDecoration(
                        border: Border.all(color: Colors.white, width: 3),
                        borderRadius: BorderRadius.circular(25),
                      ),
                    ),
                  ),
                ),
                if (_reading) const Center(child: CircularProgressIndicator()),
              ],
            ),
          ),
        ),
        if (_error != null) ...[
          const SizedBox(height: 12),
          _ErrorMessage(message: _error!),
        ],
        const SizedBox(height: 14),
        OutlinedButton.icon(
          onPressed: _reading ? null : _chooseFile,
          icon: const Icon(Icons.file_open_outlined),
          label: const Text('导入配对文件'),
          style: OutlinedButton.styleFrom(
            foregroundColor: RivlenColors.wine,
            minimumSize: const Size.fromHeight(52),
            side: const BorderSide(color: RivlenColors.line),
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(16),
            ),
          ),
        ),
      ],
    ),
  );

  Widget _pairingForm() {
    final file = _pairingFile!;
    final uri = Uri.parse(file.gatewayUrl);
    return ListView(
      padding: const EdgeInsets.fromLTRB(22, 12, 22, 28),
      children: [
        const Text(
          '授权此设备',
          style: TextStyle(
            color: RivlenColors.ink,
            fontSize: 24,
            fontWeight: FontWeight.w700,
            letterSpacing: -0.5,
          ),
        ),
        const SizedBox(height: 17),
        Container(
          decoration: BoxDecoration(
            color: RivlenColors.surface,
            borderRadius: BorderRadius.circular(18),
            border: Border.all(color: RivlenColors.line),
          ),
          padding: const EdgeInsets.all(16),
          child: Row(
            children: [
              const Icon(Icons.hub_outlined, color: RivlenColors.wine),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      uri.host,
                      style: const TextStyle(
                        color: RivlenColors.ink,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                    const SizedBox(height: 3),
                    Text(
                      '配对文件有效至 ${_time(file.expiresAt)}',
                      style: const TextStyle(
                        color: RivlenColors.muted,
                        fontSize: 12,
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
        const SizedBox(height: 22),
        TextField(
          controller: _deviceName,
          textInputAction: TextInputAction.next,
          decoration: const InputDecoration(
            labelText: '设备名称',
            prefixIcon: Icon(Icons.devices_outlined),
          ),
        ),
        const SizedBox(height: 12),
        TextField(
          controller: _password,
          obscureText: !_showPassword,
          textInputAction: TextInputAction.done,
          onSubmitted: (_) => _pair(),
          decoration: InputDecoration(
            labelText: '网关配对密码',
            prefixIcon: const Icon(Icons.lock_outline_rounded),
            suffixIcon: IconButton(
              onPressed: () => setState(() => _showPassword = !_showPassword),
              icon: Icon(
                _showPassword
                    ? Icons.visibility_off_outlined
                    : Icons.visibility_outlined,
              ),
            ),
          ),
        ),
        if (_error != null) ...[
          const SizedBox(height: 12),
          _ErrorMessage(message: _error!),
        ],
        const SizedBox(height: 24),
        FilledButton(
          onPressed: _pairing ? null : _pair,
          style: FilledButton.styleFrom(
            backgroundColor: RivlenColors.wine,
            foregroundColor: Colors.white,
            minimumSize: const Size.fromHeight(54),
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(17),
            ),
          ),
          child: _pairing
              ? const SizedBox(
                  width: 21,
                  height: 21,
                  child: CircularProgressIndicator(
                    strokeWidth: 2,
                    color: Colors.white,
                  ),
                )
              : const Text('授权并读取 Flow'),
        ),
        const SizedBox(height: 12),
        TextButton.icon(
          onPressed: _pairing
              ? null
              : () => setState(() {
                  _pairingFile = null;
                  _password.clear();
                  _error = null;
                  _scanner.start();
                }),
          icon: const Icon(Icons.qr_code_scanner_rounded),
          label: const Text('重新扫描或导入'),
          style: TextButton.styleFrom(foregroundColor: RivlenColors.muted),
        ),
      ],
    );
  }

  String _time(DateTime value) {
    final local = value.toLocal();
    String two(int number) => number.toString().padLeft(2, '0');
    return '${local.year}-${two(local.month)}-${two(local.day)} ${two(local.hour)}:${two(local.minute)}';
  }
}

class _ErrorMessage extends StatelessWidget {
  const _ErrorMessage({required this.message});

  final String message;

  @override
  Widget build(BuildContext context) => Container(
    decoration: BoxDecoration(
      color: const Color(0xFFFFF0EE),
      borderRadius: BorderRadius.circular(13),
    ),
    padding: const EdgeInsets.symmetric(horizontal: 13, vertical: 11),
    child: Text(
      message,
      style: const TextStyle(color: Color(0xFF9F3136), fontSize: 13),
    ),
  );
}
