import 'dart:async';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:camera/camera.dart';
import 'package:permission_handler/permission_handler.dart';
import 'package:tflite/tflite.dart';

class HomeScreen extends StatefulWidget {
  const HomeScreen({Key? key}) : super(key: key);

  @override
  _HomeScreenState createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen> {
  List<CameraDescription> _cameras = [];
  bool _detecting = false;
  CameraController? _controller;
  StreamController<List> _objController = StreamController<List>.broadcast();

  @override
  void dispose() {
    if (_controller != null) _controller!.dispose();
    _objController.close();
    Tflite.close();
    super.dispose();
  }

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance!.addPostFrameCallback((timeStamp) async {
      await initTflite();
      await initCamera();
      setState(() {});
    });
  }

  Future<void> initTflite() async {
    await Tflite.loadModel(
      model: 'assets/pinus.tflite',
      labels: 'assets/label.txt',
    );
  }

  Future<void> initCamera() async {
    _cameras = await availableCameras();
    await Permission.camera.request();
    _controller = CameraController(
      _cameras.first,
      ResolutionPreset.medium,
      enableAudio: false,
      // imageFormatGroup:
      //     Platform.isIOS ? ImageFormatGroup.bgra8888 : ImageFormatGroup.jpeg,
      imageFormatGroup: ImageFormatGroup.yuv420,
    );
    await _controller!.initialize();
  }

  Future<void> switchDetection() async {
    if (_detecting) {
      await _controller!.stopImageStream();
    } else {
      await _controller!
          .startImageStream((image) async => detectObjectOnFrame(image));
    }
    setState(() => _detecting = !_detecting);
  }

  Future<void> detectObjectOnFrame(CameraImage image) async {
    final recognitions = await Tflite.detectObjectOnFrame(
      bytesList: image.planes.map((plane) {
        return plane.bytes;
      }).toList(),
      model: "SSDMobileNet",
      imageHeight: image.height,
      imageWidth: image.width,
      numResultsPerClass: 1000,
    );
    _objController.add(recognitions ?? []);
  }

  List<Widget> _renderObjects(double cameraPreviewWidth, List recognitions) {
    final textHeight = 20.0;
    final cameraPreviewHeight =
        cameraPreviewWidth * _controller!.value.aspectRatio;

    return recognitions.map((recog) {
      final perc =
          ((recog['confidenceInClass'] * 100) as double).toStringAsFixed(0);

      return Positioned(
          left: recog['rect']['x'] * cameraPreviewWidth,
          top: recog['rect']['y'] * cameraPreviewHeight - textHeight,
          child: Column(
            children: [
              Container(
                height: textHeight,
                child: Text(
                  '${recog['detectedClass']} $perc%',
                  style: TextStyle(
                    color: Colors.white,
                    fontWeight: FontWeight.bold,
                  ),
                ),
              ),
              Container(
                width: recog['rect']['w'] * cameraPreviewWidth,
                height: recog['rect']['h'] * cameraPreviewHeight,
                decoration: BoxDecoration(
                    border: Border.all(
                  color: Colors.amber,
                  width: 2,
                )),
              ),
            ],
          ));
    }).toList();
  }

  @override
  Widget build(BuildContext context) {
    final size = MediaQuery.of(context).size;
    String count = '';

    if (_controller == null || !_controller!.value.isInitialized) {
      return const Scaffold();
    } else {
      return GestureDetector(
        onTap: () => FocusScope.of(context).unfocus(),
        child: Scaffold(
          backgroundColor: Colors.black,
          appBar: AppBar(
            title: const Text(
              'WoodDetection',
              style: TextStyle(
                fontWeight: FontWeight.bold,
              ),
            ),
            toolbarHeight: 30,
          ),
          floatingActionButtonLocation:
              FloatingActionButtonLocation.centerFloat,
          floatingActionButton: FloatingActionButton(
            child: Icon(_detecting ? Icons.search : Icons.search_off),
            backgroundColor: _detecting ? null : Colors.grey,
            onPressed: switchDetection,
          ),
          body: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              CameraPreview(
                _controller!,
                child: StreamBuilder<List>(
                  stream: _objController.stream,
                  builder: (_, snapshot) {
                    if (_detecting) {
                      List<Widget> list = [];
                      if (snapshot.hasData &&
                          snapshot.data != null &&
                          snapshot.data!.isNotEmpty) {
                        count = '${snapshot.data!.length} objetos encontrados';
                        list = [
                          ..._renderObjects(size.width, snapshot.data!),
                        ];
                      } else {
                        count = '';
                      }
                      return Stack(
                        alignment: Alignment.bottomCenter,
                        children: list,
                      );
                    } else {
                      return SizedBox();
                    }
                  },
                ),
              ),
              StreamBuilder<Object>(
                  stream: _objController.stream,
                  builder: (_, __) {
                    if (count != '') {
                      return SizedBox(
                        height: 15,
                        child: Text(
                          count,
                          style: TextStyle(
                            color: Colors.white,
                            fontWeight: FontWeight.bold,
                            fontSize: 18,
                          ),
                        ),
                      );
                    } else {
                      return SizedBox(height: 15);
                    }
                  }),
              // Padding(
              //   padding: const EdgeInsets.symmetric(horizontal: 20),
              //   child: Row(
              //     children: [
              //       Text('Comprimento (cm): ',
              //           style: TextStyle(color: Colors.white)),
              //       SizedBox(
              //         width: 100,
              //         child: TextFormField(
              //           style: TextStyle(color: Colors.white),
              //           keyboardType: TextInputType.number,
              //           decoration: InputDecoration(
              //             isDense: true,
              //             enabledBorder: UnderlineInputBorder(
              //                 borderSide: BorderSide(color: Colors.white)),
              //           ),
              //         ),
              //       ),
              //     ],
              //   ),
              // )
            ],
          ),
        ),
      );
    }
  }
}
