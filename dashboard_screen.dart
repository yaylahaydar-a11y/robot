import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';
import '../providers/bluetooth_provider.dart';
import 'package:font_awesome_flutter/font_awesome_flutter.dart';

class DashboardScreen extends StatefulWidget {
  const DashboardScreen({super.key});

  @override
  State<DashboardScreen> createState() => _DashboardScreenState();
}

class _DashboardScreenState extends State<DashboardScreen> {
  bool _showRawLogs = false;

  void _startMovement(String command, BluetoothProvider provider) {
    provider.startMovement(command);
    HapticFeedback.lightImpact();
  }

  void _stopMovement(BluetoothProvider provider) {
    provider.stopMovement();
    HapticFeedback.lightImpact();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: Container(
        decoration: const BoxDecoration(
          gradient: LinearGradient(
            begin: Alignment.topCenter,
            end: Alignment.bottomCenter,
            colors: [Color(0xFF1A1A2E), Color(0xFF16213E)],
          ),
        ),
        child: SafeArea(
          child: Column(
            children: [
              _buildAppBar(context),
              Expanded(
                child: SingleChildScrollView(
                  child: Column(
                    children: [
                      _buildFireStatusCard(context),
                      const SizedBox(height: 16),
                      _buildSensorCard(context),
                      const SizedBox(height: 16),
                      _buildControlPanel(context),
                      const SizedBox(height: 16),
                      _buildDirectionalPad(context),
                      const SizedBox(height: 16),
                      _buildAlertsCard(context),
                      const SizedBox(height: 16),
                      _buildCommandHistory(context),
                      _buildLogsToggle(),
                      if (_showRawLogs) _buildRawLogsPanel(context),
                      const SizedBox(height: 20),
                    ],
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildAppBar(BuildContext context) {
    final provider = Provider.of<BluetoothProvider>(context);
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 20),
      child: Row(
        children: [
          IconButton(
            icon: const Icon(Icons.arrow_back_ios_new, color: Colors.white, size: 20),
            onPressed: () {
              // Disconnect and go back to connection screen
              provider.disconnect();
              Navigator.of(context).pop();
            },
          ),
          const Expanded(
            child: Text(
              'FireBot Control',
              style: TextStyle(fontSize: 22, fontWeight: FontWeight.bold, color: Colors.white),
              overflow: TextOverflow.ellipsis,
            ),
          ),
          Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              if (provider.isEmergencyActive)
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                  margin: const EdgeInsets.only(right: 8),
                  decoration: BoxDecoration(color: Colors.red, borderRadius: BorderRadius.circular(12)),
                  child: const Text('EMERGENCY', style: TextStyle(color: Colors.white, fontSize: 10, fontWeight: FontWeight.bold)),
                ),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                decoration: BoxDecoration(
                  color: provider.isConnected ? Colors.green : Colors.red,
                  borderRadius: BorderRadius.circular(20),
                ),
                child: Row(
                  children: [
                    Container(width: 8, height: 8, decoration: const BoxDecoration(shape: BoxShape.circle, color: Colors.white)),
                    const SizedBox(width: 6),
                    Text(
                      provider.isConnected ? 'Connected' : 'Disconnected',
                      style: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 10),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildFireStatusCard(BuildContext context) {
    final provider = Provider.of<BluetoothProvider>(context);
    bool isFire = provider.fireDetected;

    return Container(
      margin: const EdgeInsets.symmetric(horizontal: 16),
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        gradient: LinearGradient(
          colors: isFire 
            ? [Colors.red.shade800, Colors.red.shade900] 
            : [Colors.green.shade800, Colors.green.shade900],
        ),
        borderRadius: BorderRadius.circular(20),
        boxShadow: [
          BoxShadow(color: (isFire ? Colors.red : Colors.green).withOpacity(0.3), blurRadius: 20, spreadRadius: 5),
        ],
      ),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(isFire ? Icons.fire_extinguisher : Icons.check_circle, size: 40, color: Colors.white),
          const SizedBox(width: 15),
          Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                isFire ? 'FIRE DETECTED!' : 'System Safe',
                style: const TextStyle(fontSize: 24, fontWeight: FontWeight.bold, color: Colors.white),
              ),
              const SizedBox(height: 5),
              Text(
                isFire ? 'LOCATION: ${provider.fireDirection} SENSOR' : 'No fire detected',
                style: const TextStyle(fontSize: 14, color: Colors.white70),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildSensorCard(BuildContext context) {
    final provider = Provider.of<BluetoothProvider>(context);
    return Container(
      margin: const EdgeInsets.symmetric(horizontal: 16),
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(color: const Color(0xFF0F3460), borderRadius: BorderRadius.circular(20)),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Row(
            children: [
              Icon(Icons.sensors, color: Colors.cyan, size: 24),
              SizedBox(width: 10),
              Text('Sensor Readings', style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold, color: Colors.white)),
            ],
          ),
          const SizedBox(height: 20),
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceEvenly,
            children: [
              _sensorInd('LEFT', provider.leftSensor, Colors.orange, provider.fireDirection == 'LEFT'),
              _sensorInd('CENTER', provider.middleSensor, Colors.yellow, provider.fireDirection == 'MIDDLE'),
              _sensorInd('RIGHT', provider.rightSensor, Colors.orange, provider.fireDirection == 'RIGHT'),
            ],
          ),
          const SizedBox(height: 16),
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceEvenly,
            children: [
              _statChip('Mode', provider.manualMode ? 'MANUAL' : 'AUTO', Colors.purple),
              _statChip('Pump', provider.pumpActive ? 'ON' : 'OFF', provider.pumpActive ? Colors.blue : Colors.grey),
              _statChip('Moving', provider.isMoving ? 'YES' : 'NO', provider.isMoving ? Colors.green : Colors.grey),
            ],
          ),
        ],
      ),
    );
  }

  Widget _sensorInd(String label, int value, Color color, bool active) {
    return Column(
      children: [
        Text(label, style: const TextStyle(color: Colors.white70, fontSize: 12)),
        const SizedBox(height: 8),
        Container(
          width: 60, height: 60,
          decoration: BoxDecoration(
            shape: BoxShape.circle,
            gradient: LinearGradient(colors: [color.withOpacity(0.3), color.withOpacity(0.1)]),
            border: Border.all(color: active ? Colors.red : color, width: active ? 3 : 2),
          ),
          child: Center(child: Text(value.toString(), style: TextStyle(fontSize: 20, fontWeight: FontWeight.bold, color: active ? Colors.red : color))),
        ),
      ],
    );
  }

  Widget _statChip(String label, String val, Color color) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
      decoration: BoxDecoration(color: color.withOpacity(0.2), borderRadius: BorderRadius.circular(12), border: Border.all(color: color)),
      child: Text('$label: $val', style: TextStyle(color: color, fontSize: 11, fontWeight: FontWeight.bold)),
    );
  }

  Widget _buildControlPanel(BuildContext context) {
    final provider = Provider.of<BluetoothProvider>(context);
    return Container(
      margin: const EdgeInsets.symmetric(horizontal: 16),
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(color: const Color(0xFF0F3460), borderRadius: BorderRadius.circular(20)),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Row(
            children: [
              Icon(Icons.gamepad, color: Colors.purple, size: 24),
              SizedBox(width: 10),
              Text('Control Panel', style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold, color: Colors.white)),
            ],
          ),
          const SizedBox(height: 20),
          Row(
            children: [
              Expanded(child: _ctrlBtn(Icons.play_arrow, 'START', 'robot_on', Colors.green, provider)),
              const SizedBox(width: 12),
              Expanded(child: _ctrlBtn(Icons.stop, 'STOP', 'robot_off', Colors.red, provider)),
            ],
          ),
          const SizedBox(height: 12),
          Row(
            children: [
              Expanded(child: _ctrlBtn(Icons.water_drop, 'PUMP ON', 'pump_on', Colors.blue, provider)),
              const SizedBox(width: 12),
              Expanded(child: _ctrlBtn(Icons.water_drop_outlined, 'PUMP OFF', 'pump_off', Colors.orange, provider)),
            ],
          ),
          const SizedBox(height: 12),
          Row(
            children: [
              Expanded(child: _ctrlBtn(Icons.touch_app, 'MANUAL', 'manual_on', Colors.purple, provider)),
              const SizedBox(width: 12),
              Expanded(child: _ctrlBtn(Icons.smart_toy, 'AUTO', 'manual_off', Colors.blueGrey, provider)),
            ],
          ),
          if (provider.isEmergencyActive) ...[
            const SizedBox(height: 12),
            _ctrlBtn(Icons.refresh, 'RESET EMERGENCY', 'reset_emergency', Colors.orange, provider, fullWidth: true),
          ],
        ],
      ),
    );
  }

  Widget _ctrlBtn(IconData icon, String label, String cmd, Color color, BluetoothProvider provider, {bool fullWidth = false}) {
    return SizedBox(
      width: fullWidth ? double.infinity : null,
      child: ElevatedButton(
        onPressed: () => provider.sendCommand(cmd),
        style: ElevatedButton.styleFrom(backgroundColor: color, padding: const EdgeInsets.symmetric(vertical: 16), shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12))),
        child: Column(children: [Icon(icon, size: 28, color: Colors.white), const SizedBox(height: 8), Text(label, style: const TextStyle(fontSize: 12, fontWeight: FontWeight.bold, color: Colors.white))]),
      ),
    );
  }

  Widget _buildDirectionalPad(BuildContext context) {
    final provider = Provider.of<BluetoothProvider>(context);
    return Container(
      margin: const EdgeInsets.symmetric(horizontal: 16),
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(color: const Color(0xFF0F3460), borderRadius: BorderRadius.circular(20)),
      child: Column(
        children: [
          const Row(children: [Icon(Icons.directions, color: Colors.cyan, size: 24), SizedBox(width: 10), Text('Movement Control', style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold, color: Colors.white))]),
          const SizedBox(height: 20),
          Center(
            child: Column(
              children: [
                _dirBtn('↑', 'f', provider),
                const SizedBox(height: 12),
                Row(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    _dirBtn('←', 'l', provider),
                    const SizedBox(width: 12),
                    GestureDetector(
                      onTap: () => provider.stopMovement(),
                      child: Container(
                        width: 70, height: 70,
                        decoration: BoxDecoration(gradient: const LinearGradient(colors: [Colors.red, Colors.redAccent]), shape: BoxShape.circle),
                        child: const Icon(Icons.stop, size: 40, color: Colors.white),
                      ),
                    ),
                    const SizedBox(width: 12),
                    _dirBtn('→', 'r', provider),
                  ],
                ),
                const SizedBox(height: 12),
                _dirBtn('↓', 'b', provider),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _dirBtn(String label, String cmd, BluetoothProvider provider) {
    return Listener(
      onPointerDown: (_) => _startMovement(cmd, provider),
      onPointerUp: (_) => _stopMovement(provider),
      child: Container(
        width: 70, height: 70,
        decoration: BoxDecoration(gradient: const LinearGradient(colors: [Colors.cyan, Colors.blue]), shape: BoxShape.circle),
        child: Center(child: Text(label, style: const TextStyle(fontSize: 32, fontWeight: FontWeight.bold, color: Colors.white))),
      ),
    );
  }

  Widget _buildAlertsCard(BuildContext context) {
    final provider = Provider.of<BluetoothProvider>(context);
    if (provider.alerts.isEmpty) return const SizedBox.shrink();
    return Container(
      margin: const EdgeInsets.symmetric(horizontal: 16),
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(color: Colors.red.shade900.withOpacity(0.2), borderRadius: BorderRadius.circular(20), border: Border.all(color: Colors.red.shade800, width: 1)),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(mainAxisAlignment: MainAxisAlignment.spaceBetween, children: [
            const Row(children: [Icon(Icons.notifications_active, color: Colors.red, size: 20), SizedBox(width: 8), Text('Recent Alerts', style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold))]),
            TextButton(onPressed: () => provider.clearAlerts(), child: const Text('Clear', style: TextStyle(color: Colors.white70, fontSize: 12))),
          ]),
          ...provider.alerts.take(5).map((a) => Padding(padding: const EdgeInsets.symmetric(vertical: 2), child: Text(a, style: const TextStyle(color: Colors.white70, fontSize: 12)))),
        ],
      ),
    );
  }

  Widget _buildCommandHistory(BuildContext context) {
    final provider = Provider.of<BluetoothProvider>(context);
    if (provider.commandHistory.isEmpty) return const SizedBox.shrink();
    return Container(
      margin: const EdgeInsets.symmetric(horizontal: 16),
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(color: const Color(0xFF0F3460).withOpacity(0.7), borderRadius: BorderRadius.circular(20)),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        const Row(children: [Icon(Icons.history, color: Colors.white70, size: 20), SizedBox(width: 8), Text('Command History', style: TextStyle(color: Colors.white70, fontWeight: FontWeight.bold))]),
        const SizedBox(height: 12),
        Wrap(spacing: 8, runSpacing: 8, children: provider.commandHistory.take(10).map((c) => Container(padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5), decoration: BoxDecoration(color: Colors.black26, borderRadius: BorderRadius.circular(15)), child: Text(c, style: const TextStyle(color: Colors.white60, fontSize: 11)))).toList()),
      ]),
    );
  }

  Widget _buildLogsToggle() {
    return TextButton(onPressed: () => setState(() => _showRawLogs = !_showRawLogs), child: Text(_showRawLogs ? 'Hide Serial Logs' : 'Show Serial Logs', style: const TextStyle(color: Colors.white24, fontSize: 11)));
  }

  Widget _buildRawLogsPanel(BuildContext context) {
    final provider = Provider.of<BluetoothProvider>(context);
    return Container(
      margin: const EdgeInsets.symmetric(horizontal: 16),
      height: 150, padding: const EdgeInsets.all(10),
      decoration: BoxDecoration(color: Colors.black, borderRadius: BorderRadius.circular(10), border: Border.all(color: Colors.green.shade900)),
      child: ListView.builder(itemCount: provider.rawLogs.length, itemBuilder: (context, i) => Text(provider.rawLogs[i], style: const TextStyle(color: Colors.greenAccent, fontSize: 10, fontFamily: 'monospace'))),
    );
  }
}
