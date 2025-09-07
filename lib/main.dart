import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:google_maps_flutter/google_maps_flutter.dart';
import 'package:geolocator/geolocator.dart';
import 'package:http/http.dart' as http;

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
  double currentZoom = 10.0;

  final TextEditingController _latCtrl = TextEditingController();
  final TextEditingController _lngCtrl = TextEditingController();

  final Set<Marker> _markers = {};
  final Set<Polyline> _polylines = {};

  final String googleApiKey = "AIzaSyBzuPglEyOj44epyY18uUJmxGdI3LBNSdQ";

  void createGoogleMap(GoogleMapController varMap) {
    map = varMap;
    _setMarker(point);
  }

  void _setMarker(LatLng target) {
    setState(() {
      _markers
        ..clear()
        ..add(
          Marker(
            markerId: const MarkerId('marker'),
            position: target,
            infoWindow: const InfoWindow(title: 'ตำแหน่งเป้าหมาย'),
          ),
        );
    });
  }

  double? _parseNum(String s) {
    try {
      return double.parse(s.trim().replaceAll(',', '.'));
    } catch (_) {
      return null;
    }
  }

  Future<void> _search() async {
    final lat = _parseNum(_latCtrl.text);
    final lng = _parseNum(_lngCtrl.text);

    if (lat == null || lng == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('กรุณากรอกค่า lat/lng ให้ถูกต้อง')),
      );
      return;
    }

    final target = LatLng(lat, lng);
    _setMarker(target);
    currentZoom = 15;

    await map.animateCamera(
      CameraUpdate.newCameraPosition(
        CameraPosition(target: target, zoom: currentZoom),
      ),
    );

    await _drawRoute(target);
  }

  Future<void> _goCurrentLocation() async {
    bool serviceEnabled;
    LocationPermission permission;

    serviceEnabled = await Geolocator.isLocationServiceEnabled();
    if (!serviceEnabled) {
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(const SnackBar(content: Text('กรุณาเปิด GPS')));
      return;
    }

    permission = await Geolocator.checkPermission();
    if (permission == LocationPermission.denied) {
      permission = await Geolocator.requestPermission();
      if (permission == LocationPermission.denied) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('ไม่ได้รับสิทธิ์เข้าถึงตำแหน่ง')),
        );
        return;
      }
    }

    if (permission == LocationPermission.deniedForever) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('แอปไม่ได้รับสิทธิ์เข้าถึงตำแหน่งถาวร')),
      );
      return;
    }

    final pos = await Geolocator.getCurrentPosition();
    final current = LatLng(pos.latitude, pos.longitude);

    _setMarker(current);

    await map.animateCamera(
      CameraUpdate.newCameraPosition(
        CameraPosition(target: current, zoom: currentZoom),
      ),
    );

    _latCtrl.text = pos.latitude.toStringAsFixed(6);
    _lngCtrl.text = pos.longitude.toStringAsFixed(6);
  }

  void _zoomIn() {
    currentZoom += 1;
    map.animateCamera(CameraUpdate.zoomTo(currentZoom));
  }

  void _zoomOut() {
    currentZoom -= 1;
    map.animateCamera(CameraUpdate.zoomTo(currentZoom));
  }

  // 🔹 ฟังก์ชันวาดเส้นทางจากตำแหน่งปัจจุบันไปยัง target
  Future<void> _drawRoute(LatLng target) async {
    final pos = await Geolocator.getCurrentPosition();
    final origin = "${pos.latitude},${pos.longitude}";
    final destination = "${target.latitude},${target.longitude}";

    final url =
        "https://maps.googleapis.com/maps/api/directions/json?origin=$origin&destination=$destination&key=$googleApiKey";

    final response = await http.get(Uri.parse(url));
    if (response.statusCode == 200) {
      final data = jsonDecode(response.body);

      if (data['status'] == 'OK') {
        final points = data['routes'][0]['overview_polyline']['points'];
        final polylineCoordinates = _decodePolyline(points);

        setState(() {
          _polylines.clear();
          _polylines.add(
            Polyline(
              polylineId: const PolylineId("route"),
              color: Colors.blue,
              width: 5,
              points: polylineCoordinates,
            ),
          );
        });

        // ซูมกล้องให้ครอบคลุมเส้นทาง
        final bounds = _boundsFromLatLngList(polylineCoordinates);
        map.animateCamera(CameraUpdate.newLatLngBounds(bounds, 50));
      } else {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text("ไม่พบเส้นทาง: ${data['status']}")),
        );
      }
    } else {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text("HTTP error: ${response.statusCode}")),
      );
    }
  }

  // แปลง encoded polyline เป็น LatLng
  List<LatLng> _decodePolyline(String encoded) {
    List<LatLng> poly = [];
    int index = 0, len = encoded.length;
    int lat = 0, lng = 0;

    while (index < len) {
      int b, shift = 0, result = 0;
      do {
        b = encoded.codeUnitAt(index++) - 63;
        result |= (b & 0x1f) << shift;
        shift += 5;
      } while (b >= 0x20);
      int dlat = ((result & 1) != 0 ? ~(result >> 1) : (result >> 1));
      lat += dlat;

      shift = 0;
      result = 0;
      do {
        b = encoded.codeUnitAt(index++) - 63;
        result |= (b & 0x1f) << shift;
        shift += 5;
      } while (b >= 0x20);
      int dlng = ((result & 1) != 0 ? ~(result >> 1) : (result >> 1));
      lng += dlng;

      poly.add(LatLng(lat / 1E5, lng / 1E5));
    }

    return poly;
  }

  // สร้าง LatLngBounds ครอบเส้นทาง
  LatLngBounds _boundsFromLatLngList(List<LatLng> list) {
    double x0 = list.first.latitude;
    double x1 = list.first.latitude;
    double y0 = list.first.longitude;
    double y1 = list.first.longitude;

    for (LatLng latLng in list) {
      if (latLng.latitude > x1) x1 = latLng.latitude;
      if (latLng.latitude < x0) x0 = latLng.latitude;
      if (latLng.longitude > y1) y1 = latLng.longitude;
      if (latLng.longitude < y0) y0 = latLng.longitude;
    }
    return LatLngBounds(southwest: LatLng(x0, y0), northeast: LatLng(x1, y1));
  }

  @override
  void dispose() {
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
          onPressed: _goCurrentLocation,
        ),
        title: const Text("แสดงแผนที่"),
        centerTitle: true,
        backgroundColor: Colors.blue,
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
            onTap: (LatLng tappedPoint) async {
              _setMarker(tappedPoint);
              _latCtrl.text = tappedPoint.latitude.toStringAsFixed(6);
              _lngCtrl.text = tappedPoint.longitude.toStringAsFixed(6);
              await _drawRoute(tappedPoint);
            },
          ),
          Positioned(
            top: 12,
            left: 12,
            right: 12,
            child: Card(
              color: Colors.pink,
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
                    Row(
                      children: [
                        Expanded(
                          child: TextField(
                            controller: _latCtrl,
                            keyboardType: const TextInputType.numberWithOptions(
                              decimal: true,
                              signed: true,
                            ),
                            textInputAction: TextInputAction.next,
                            decoration: const InputDecoration(
                              labelText: 'ละติจูด (lat)',
                              hintText: 'เช่น 16.1872',
                            ),
                          ),
                        ),
                        const SizedBox(width: 12),
                        Expanded(
                          child: TextField(
                            controller: _lngCtrl,
                            keyboardType: const TextInputType.numberWithOptions(
                              decimal: true,
                              signed: true,
                            ),
                            textInputAction: TextInputAction.done,
                            decoration: const InputDecoration(
                              labelText: 'ลองจิจูด (lng)',
                              hintText: 'เช่น 103.3045',
                            ),
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 8),
                    SizedBox(
                      width: double.infinity,
                      child: ElevatedButton.icon(
                        onPressed: _search,
                        icon: const Icon(Icons.search),
                        label: const Text('ค้นหา'),
                        style: ElevatedButton.styleFrom(
                          padding: const EdgeInsets.symmetric(vertical: 12),
                          backgroundColor: const Color.fromARGB(
                            255,
                            213,
                            182,
                            57,
                          ),
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
        ],
      ),
    );
  }
}
