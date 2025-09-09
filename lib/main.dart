import 'dart:async';
import 'package:flutter/material.dart';
import 'package:google_maps_flutter/google_maps_flutter.dart';
import 'package:geolocator/geolocator.dart';

void main() {
  runApp(const Map01());
}

class Map01 extends StatelessWidget {
  const Map01({super.key});

  @override
  Widget build(BuildContext context) {
    return const MaterialApp(debugShowCheckedModeBanner: false, home: AppMap());
  }
}

class AppMap extends StatefulWidget {
  const AppMap({super.key});

  @override
  State<AppMap> createState() => _AppMapState();
}

class _AppMapState extends State<AppMap> {
  late GoogleMapController map;
  LatLng point = const LatLng(16.1872, 103.3045);
  double currentZoom = 20.0;

  final TextEditingController _latCtrl = TextEditingController();
  final TextEditingController _lngCtrl = TextEditingController();

  final Set<Marker> _markers = {};
  final Set<Polyline> _polylines = {};
  final List<LatLng> _trailPoints = [];
  double _totalDistance = 0.0; // เพิ่มตัวแปรเก็บระยะทางรวม

  StreamSubscription<Position>? _positionStream;

  LatLng? _destinationLatLng;
  BitmapDescriptor? _carIcon;

  @override
  void initState() {
    super.initState();
    _checkPermission();

    // ดึงตำแหน่งล่าสุดทันทีตอนเปิดแอป
    Geolocator.getCurrentPosition(
      locationSettings: const LocationSettings(
        accuracy: LocationAccuracy.bestForNavigation,
      ),
    ).then((pos) {
      _updatePosition(pos, moveCamera: true);
    });

    // Subscribe stream ต่อเนื่อง
    _positionStream =
        Geolocator.getPositionStream(
          locationSettings: const LocationSettings(
            accuracy: LocationAccuracy.bestForNavigation,
            distanceFilter: 0,
          ),
        ).listen((Position pos) {
          _updatePosition(pos);
        });
  }

  // ฟังก์ชันใหม่: อัปเดต Marker รถแบบเรียบ
  void _updateMarkerPosition(LatLng newPos) {
    final oldMarker = _markers.firstWhere(
      (m) => m.markerId.value == 'current',
      orElse: () =>
          Marker(markerId: const MarkerId('current'), position: newPos),
    );

    final updatedMarker = oldMarker.copyWith(
      positionParam: newPos,
      iconParam: BitmapDescriptor.defaultMarkerWithHue(
        BitmapDescriptor.hueBlue,
      ), // สีน้ำเงิน
    );

    _markers.removeWhere((m) => m.markerId.value == 'current');
    _markers.add(updatedMarker);
  }

  void _updatePosition(Position pos, {bool moveCamera = false}) {
    final current = LatLng(pos.latitude, pos.longitude);

    // อัปเดต Marker รถแบบเรียบ
    _updateMarkerPosition(current);

    // update trail
    if (_trailPoints.isNotEmpty) {
      final last = _trailPoints.last;
      final dist = Geolocator.distanceBetween(
        last.latitude,
        last.longitude,
        current.latitude,
        current.longitude,
      );
      _totalDistance += dist;
    }
    _trailPoints.add(current);
    if (_trailPoints.length > 50) _trailPoints.removeAt(0);

    _polylines.removeWhere((p) => p.polylineId.value == 'trail');
    _polylines.add(
      Polyline(
        polylineId: const PolylineId('trail'),
        color: Colors.green,
        width: 4,
        points: List.from(_trailPoints),
      ),
    );

    // **ไม่เคลื่อนกล้องอัตโนมัติอีกต่อไป**
    if (moveCamera) {
      map.animateCamera(
        CameraUpdate.newLatLng(current),
      ); // เฉพาะตอนกดปุ่มซ้ายบน
    }

    _latCtrl.text = pos.latitude.toStringAsFixed(6);
    _lngCtrl.text = pos.longitude.toStringAsFixed(6);

    // เช็คใกล้ Marker ปลายทาง
    if (_destinationLatLng != null) {
      final dist = Geolocator.distanceBetween(
        current.latitude,
        current.longitude,
        _destinationLatLng!.latitude,
        _destinationLatLng!.longitude,
      );

      if (dist < 10) {
        _markers.removeWhere((m) => m.markerId.value == 'destination');
        _destinationLatLng = null;

        showDialog(
          context: context,
          builder: (context) => AlertDialog(
            title: const Text('ถึงจุดหมายแล้ว!'),
            content: const Text('คุณได้เดินทางมาถึงจุดหมายเรียบร้อยแล้ว'),
            actions: [
              TextButton(
                onPressed: () => Navigator.of(context).pop(),
                child: const Text('ปิด'),
              ),
            ],
          ),
        );
      }
    }

    setState(() {});
  }

  void _clearMarkersAndTrail() {
    setState(() {
      _markers.removeWhere((m) => m.markerId.value == 'destination');
      _trailPoints.clear();
      _polylines.removeWhere((p) => p.polylineId.value == 'trail');
      _destinationLatLng = null;
      _totalDistance = 0.0; // reset ระยะทางด้วย
    });
  }

  Future<void> _checkPermission() async {
    LocationPermission permission = await Geolocator.checkPermission();

    if (permission == LocationPermission.denied) {
      permission = await Geolocator.requestPermission();
    }

    if (permission == LocationPermission.deniedForever) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('กรุณาเปิด Permission Location ใน Settings'),
        ),
      );
      return;
    }

    if (permission == LocationPermission.whileInUse) {
      permission =
          await Geolocator.requestPermission(); // ขอ background ถ้าได้แค่ whileInUse
    }
  }

  Future<void> _goCurrentLocation() async {
    try {
      final pos = await Geolocator.getCurrentPosition(
        locationSettings: const LocationSettings(
          accuracy: LocationAccuracy.bestForNavigation,
        ),
      );

      _updatePosition(pos, moveCamera: true); // จะ animate กล้องตอนกดปุ่ม
    } catch (e) {
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text('Error: $e')));
    }
  }

  void createGoogleMap(GoogleMapController varMap) {
    map = varMap;
  }

  void _setMarker(LatLng target, {bool isCurrent = false}) {
    setState(() {
      if (isCurrent) return;

      _markers.removeWhere((m) => m.markerId.value == 'destination');
      _markers.add(
        Marker(
          markerId: const MarkerId('destination'),
          position: target,
          icon: BitmapDescriptor.defaultMarkerWithHue(BitmapDescriptor.hueRed),
          infoWindow: const InfoWindow(title: 'ปลายทาง'),
        ),
      );
      _destinationLatLng = target;
    });
  }

  void _zoomIn() {
    currentZoom += 1;
    map.animateCamera(CameraUpdate.zoomTo(currentZoom));
  }

  void _zoomOut() {
    currentZoom -= 1;
    map.animateCamera(CameraUpdate.zoomTo(currentZoom));
  }

  @override
  void dispose() {
    _positionStream?.cancel();
    _latCtrl.dispose();
    _lngCtrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        leading: IconButton(
          icon: const Icon(Icons.my_location),
          onPressed:
              _goCurrentLocation, // ฟังก์ชันนี้จะอัปเดตกล้องไปตำแหน่ง Marker
        ),

        title: const Text("GPS"),
        centerTitle: true,
        backgroundColor: Colors.blue,
        actions: [
          IconButton(
            icon: const Icon(Icons.refresh_sharp),
            onPressed: _clearMarkersAndTrail,
          ),
        ],
      ),
      body: Stack(
        children: [
          GoogleMap(
            onMapCreated: createGoogleMap,
            initialCameraPosition: CameraPosition(
              target: point,
              zoom: currentZoom,
            ),
            markers: _markers,
            polylines: _polylines,
            myLocationButtonEnabled: false,
            zoomControlsEnabled: false,
            onTap: (LatLng tappedPoint) {
              _setMarker(tappedPoint);
              _latCtrl.text = tappedPoint.latitude.toStringAsFixed(6);
              _lngCtrl.text = tappedPoint.longitude.toStringAsFixed(6);
            },
          ),
          Positioned(
            top: 12,
            left: 12,
            right: 12,
            child: Card(
              color: Colors.blue,
              elevation: 4,
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(12),
              ),
              child: Padding(
                padding: const EdgeInsets.symmetric(
                  horizontal: 12,
                  vertical: 8,
                ),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Center(
                      child: Text(
                        'ตำแหน่งปัจจุบัน',
                        style: const TextStyle(
                          color: Colors.white,
                          fontWeight: FontWeight.bold,
                          fontSize: 16,
                        ),
                      ),
                    ),
                    const SizedBox(height: 8),
                    Row(
                      children: [
                        Expanded(
                          child: Text(
                            'ละติจูด: ${_latCtrl.text}',
                            style: const TextStyle(
                              color: Colors.white,
                              fontWeight: FontWeight.bold,
                            ),
                          ),
                        ),
                        const SizedBox(width: 12),
                        Expanded(
                          child: Text(
                            'ลองจิจูด: ${_lngCtrl.text}',
                            style: const TextStyle(
                              color: Colors.white,
                              fontWeight: FontWeight.bold,
                            ),
                          ),
                        ),
                      ],
                    ),
                    if (_destinationLatLng != null)
                      Padding(
                        padding: const EdgeInsets.only(top: 8.0),
                        child: Text(
                          "ปลายทาง: ${_destinationLatLng!.latitude.toStringAsFixed(6)}, ${_destinationLatLng!.longitude.toStringAsFixed(6)}",
                          style: const TextStyle(
                            fontWeight: FontWeight.bold,
                            color: Colors.white,
                          ),
                        ),
                      ),
                  ],
                ),
              ),
            ),
          ),
          Positioned(
            bottom: 20,
            right: 20,
            child: Column(
              children: [
                FloatingActionButton(
                  onPressed: _zoomIn,
                  heroTag: 'zoomIn',
                  mini: true,
                  backgroundColor: Colors.blue,
                  child: const Icon(Icons.add),
                ),
                const SizedBox(height: 8),
                FloatingActionButton(
                  onPressed: _zoomOut,
                  heroTag: 'zoomOut',
                  mini: true,
                  backgroundColor: Colors.blue,
                  child: const Icon(Icons.remove),
                ),
              ],
            ),
          ),
          Positioned(
            top: 120,
            left: 12,
            child: Card(
              color: Colors.black54,
              child: Padding(
                padding: const EdgeInsets.all(8.0),
                child: Text(
                  "เคลื่อนที่ไปแล้ว: ${_totalDistance.toStringAsFixed(1)} เมตร",
                  style: const TextStyle(
                    color: Colors.white,
                    fontWeight: FontWeight.bold,
                  ),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}
