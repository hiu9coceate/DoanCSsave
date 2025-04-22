import 'dart:io';
import 'package:flutter/material.dart';
// import 'package:flutter/services.dart'; // Có thể không cần nếu không dùng các service cụ thể
import 'package:camera/camera.dart';
// Loại bỏ tflite_flutter vì không chạy mô hình cục bộ nữa
// import 'package:tflite_flutter/tflite_flutter.dart';
import 'dart:typed_data';
import 'dart:convert'; // Cần cho jsonEncode và jsonDecode
// import 'package:flutter/services.dart' show rootBundle; // Không cần load label map cục bộ nữa
// import 'package:image/image.dart' as img; // Có thể không cần nếu không xử lý ảnh trước khi gửi
import 'package:http/http.dart' as http; // Thêm thư viện http
import 'package:image_picker/image_picker.dart'; // Thêm thư viện image_picker (nếu bạn dùng nó để lấy ảnh)


// Hàm main giữ nguyên để khởi tạo camera và chạy ứng dụng
Future<void> main() async {
  // Ensure that plugin services are initialized so that `availableCameras()`
  // can be called before `runApp()`.
  WidgetsFlutterBinding.ensureInitialized();

  // Retrieve the list of available cameras.
  final cameras = await availableCameras();

  // Get a specific camera from the list.
  final firstCamera = cameras.first;

  runApp(MaterialApp(
    title: 'Nhận Diện Thủ Ngữ', // Tên ứng dụng
    theme: ThemeData(
      primarySwatch: Colors.blue,
      visualDensity: VisualDensity.adaptivePlatformDensity,
    ),
    home: HomeScreen(camera: firstCamera),
  ));
}

// HomeScreen widget (StatefulWidget)
class HomeScreen extends StatefulWidget {
  final CameraDescription camera;

  const HomeScreen({Key? key, required this.camera}) : super(key: key);

  @override
  _HomeScreenState createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen> {
  late CameraController _controller;
  late Future<void> _initializeControllerFuture;
  String recognizedText = ''; // Biến lưu kết quả, sẽ tích lũy
  bool isProcessing = false;

  // --- Các biến liên quan đến TFLite không còn cần thiết ---
  // Interpreter? interpreter;
  // Map<int, String> gestureMap = {};
  // static const int numLandmarks = 21;
  // static const int numCoordinates = 3;

  // --- Cấu hình API Server ---
  // Địa chỉ API của server Python của bạn
  // RẤT QUAN TRỌNG: Thay thế 'YOUR_SERVER_IP_OR_DOMAIN' bằng IP hoặc tên miền thực tế
  // của máy tính đang chạy server Flask.
  // Ví dụ: 'http://192.168.1.100:5000/predict'
  // Nếu dùng Android emulator: 'http://10.0.2.2:5000/predict'
  // Nếu dùng iOS simulator: 'http://localhost:5000/predict'
  final String apiUrl = 'http://192.168.1.9:5000/predict'; // <-- Đảm bảo địa chỉ này đúng

  // --- Các hàm liên quan đến TFLite không còn cần thiết ---
  // Future<void> _loadLabelMap() async { ... }
  // Future<void> _loadModel() async { ... }
  // Future<List<double>?> _extractHandLandmarks(File imageFile) async { ... }
  // Float32List _preProcessLandmarks(List<double> landmarks) { ... }
  // Future<String?> processHandGestureWithTFLite(File imageFile) async { ... }


  // --- Hàm mới để gửi ảnh lên server và nhận kết quả ---
  Future<String?> processHandGestureWithAPI(File imageFile) async {
    try {
      // Cập nhật trạng thái UI: Đang xử lý
      setState(() {
         isProcessing = true;
         recognizedText = (recognizedText.isEmpty ? '' : recognizedText + '\n') + 'Đang gửi ảnh lên server...'; // Thêm vào cuối
      });

      // Đọc ảnh dưới dạng bytes
      List<int> imageBytes = await imageFile.readAsBytes();
      // Chuyển bytes ảnh sang định dạng Base64 để gửi qua JSON
      String base64Image = base64Encode(imageBytes);

      // Tạo body request dạng JSON
      final Map<String, String> requestBody = {
        'image': base64Image, // Key 'image' phải khớp với key server mong đợi ('image')
      };

      // Gửi request POST đến API server
      final response = await http.post(
        Uri.parse(apiUrl), // Phân tích chuỗi URL
        headers: {
          'Content-Type': 'application/json', // Đặt header là JSON
        },
        body: jsonEncode(requestBody), // Chuyển Map sang chuỗi JSON
      );

      // --- Xử lý phản hồi từ server ---
      if (response.statusCode == 200) {
        // Server trả về thành công (HTTP status code 200 OK)
        final Map<String, dynamic> responseData = jsonDecode(response.body); // Giải mã JSON

        // Kiểm tra nội dung JSON phản hồi từ server (Server trả về {'predicted_label': ..., 'confidence': ...} hoặc {'message': ...})
        if (responseData.containsKey('predicted_label')) {
          // Nhận được kết quả dự đoán từ server
          final String predictedLabel = responseData['predicted_label'];
          final double confidence = responseData['confidence']; // Đảm bảo kiểu dữ liệu double

          // Trả về chuỗi kết quả để hiển thị
          return "$predictedLabel (${(confidence * 100).toStringAsFixed(1)}%)";

        } else if (responseData.containsKey('message')) {
           // Server trả về thông báo (ví dụ: không phát hiện tay)
           return responseData['message'].toString(); // Đảm bảo là String
        }
        else {
           // Định dạng phản hồi không như mong đợi
           print('Lỗi định dạng phản hồi từ server: ${response.body}');
           return "Lỗi: Định dạng phản hồi từ server không hợp lệ.";
        }

      } else {
        // Server trả về mã lỗi (ví dụ: 400 Bad Request, 500 Internal Server Error)
        print('Lỗi API: ${response.statusCode}');
        print('Phản hồi lỗi từ server: ${response.body}');
        try {
             // Cố gắng giải mã phản hồi lỗi để lấy thông báo chi tiết từ server nếu có
             final Map<String, dynamic> errorData = jsonDecode(response.body);
             if(errorData.containsKey('error')){
                 return "Lỗi Server: ${errorData['error']}";
             } else {
                 return "Lỗi Server: Status Code ${response.statusCode}";
             }
        } catch (e){
            // Nếu không giải mã được phản hồi lỗi
            return "Lỗi Server: Status Code ${response.statusCode}";
        }
      }
    } catch (e) {
      // --- Bắt các lỗi khác (lỗi mạng, lỗi xử lý request, v.v.) ---
      print("Lỗi khi gửi ảnh đến server: $e");
      return "Lỗi Kết Nối: $e"; // Trả về thông báo lỗi kết nối
    } finally {
       // --- Luôn đặt lại trạng thái isProcessing sau khi hoàn thành hoặc gặp lỗi ---
       setState(() {
          isProcessing = false;
       });
    }
  }


  // Hàm chụp ảnh, gọi hàm xử lý với API sau khi chụp
  Future<void> takePicture() async {
    try {
      // Ensure the controller is initialized before taking the picture.
      await _initializeControllerFuture;

      // Không cần đặt isProcessing = true ở đây nữa, đã làm trong processHandGestureWithAPI
      // setState(() {
      //   isProcessing = true;
      //   recognizedText = 'Đang xử lý...';
      // });

      // BẬT ĐÈN FLASH
      await _controller.setFlashMode(FlashMode.auto);


      // Chụp ảnh
      final XFile photo = await _controller.takePicture();
      final File imageFile = File(photo.path); // Lấy file ảnh từ XFile

      // TẮT ĐÈN FLASH sau khi chụp
      await _controller.setFlashMode(FlashMode.auto);


      // Gọi hàm xử lý ảnh bằng cách gửi lên API server
      final result = await processHandGestureWithAPI(imageFile);

      // Cập nhật giao diện người dùng với kết quả hoặc thông báo
      // isProcessing đã được đặt false trong processHandGestureWithAPI finally block
      setState(() {
         // Thêm kết quả mới vào cuối chuỗi recognizedText
         if (result != null) {
            recognizedText = (recognizedText.isEmpty ? '' : recognizedText + '\n') + 'Kết quả: ' + result; // Thêm kết quả mới với xuống dòng nếu chuỗi không rỗng
         } else {
            recognizedText = (recognizedText.isEmpty ? '' : recognizedText + '\n') + "Không nhận diện được thủ ngữ."; // Thêm thông báo không nhận diện
         }
      });

    } catch (e) {
      // Nếu có lỗi khi chụp ảnh hoặc xử lý ban đầu
      print('Lỗi khi chụp ảnh: $e');
      setState(() {
        isProcessing = false; // Đảm bảo tắt cờ xử lý
        recognizedText = (recognizedText.isEmpty ? '' : recognizedText + '\n') + "Lỗi chụp ảnh: $e"; // Thêm thông báo lỗi chụp ảnh
      });
    }
  }

  // Hàm xóa kết quả hiển thị
  void clearResults() {
    setState(() {
      recognizedText = ''; // Đặt lại chuỗi kết quả về rỗng
    });
  }

  @override
  void initState() {
    super.initState();

    // Khởi tạo CameraController
    _controller = CameraController(
      widget.camera, // Camera được truyền vào từ main
      ResolutionPreset.medium, // Độ phân giải
      enableAudio: false, // Tắt âm thanh nếu không cần
    );

    // Bắt đầu quá trình khởi tạo controller, trả về Future
    _initializeControllerFuture = _controller.initialize().then((_) {
       // Đặt chế độ flash ban đầu (ví dụ: tắt) sau khi controller được khởi tạo thành công
       _controller.setFlashMode(FlashMode.off);
       // Cập nhật UI nếu cần sau khi camera sẵn sàng (ví dụ: ẩn loading ban đầu)
       setState(() {});
    }).catchError((Object e) {
       // Xử lý lỗi khởi tạo camera
       if (e is CameraException) {
         switch (e.code) {
           case 'CameraAccessDenied':
             print('Lỗi: Quyền truy cập camera bị từ chối.');
             recognizedText = 'Quyền truy cập camera bị từ chối.';
             break;
           default:
             print('Lỗi khởi tạo camera không xác định: ${e.code}');
             recognizedText = 'Lỗi camera: ${e.description ?? e.code}';
             break;
         }
       } else {
          print('Lỗi không xác định khi khởi tạo camera: $e');
          recognizedText = 'Lỗi khởi tạo camera không xác định.';
       }
       setState(() {}); // Cập nhật UI để hiển thị thông báo lỗi
    });

    // --- Các lệnh load model/label map cục bộ không còn cần thiết ---
    // _loadModel();
    // _loadLabelMap();
  }

  @override
  void dispose() {
    // Giải phóng CameraController khi widget bị loại bỏ
    _controller.dispose();
    // --- Giải phóng interpreter TFLite không còn cần thiết ---
    // interpreter?.close();
    super.dispose();
  }

  // --- Xây dựng giao diện người dùng ---
  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Nhận Diện Thủ Ngữ'),
        backgroundColor: Colors.blue,
      ),
      body: Column(
        children: [
          // Phần hiển thị Camera Preview
          Expanded(
            flex: 3, // Chiếm 3 phần không gian
            child: FutureBuilder<void>(
              future: _initializeControllerFuture, // Chờ Future khởi tạo controller
              builder: (context, snapshot) {
                if (snapshot.connectionState == ConnectionState.done) {
                   // Khi Future hoàn thành, kiểm tra controller đã khởi tạo chưa
                   if (_controller.value.isInitialized) {
                     return CameraPreview(_controller); // Hiển thị Camera Preview
                   } else {
                     // Hiển thị lỗi nếu camera không khởi tạo được
                     return Center(
                         child: Text(recognizedText.isNotEmpty ? recognizedText : 'Đang khởi tạo camera...', // Hiển thị lỗi khởi tạo camera
                                     textAlign: TextAlign.center,
                                     style: TextStyle(color: Colors.red, fontSize: 18)));
                   }
                } else {
                  // Trong khi Future đang chạy, hiển thị loading indicator
                  return const Center(child: CircularProgressIndicator());
                }
              },
            ),
          ),

          // Nút Chụp
          Padding(
            padding: const EdgeInsets.symmetric(vertical: 10.0),
            child: ElevatedButton(
              // Vô hiệu hóa nút khi đang xử lý hoặc camera chưa sẵn sàng
              onPressed: isProcessing || !_controller.value.isInitialized ? null : takePicture,
              child: isProcessing
                  ? const CircularProgressIndicator(color: Colors.white) // Hiển thị loading khi đang xử lý
                  : const Text('Chụp'),
            ),
          ),

          // Phần hiển thị kết quả
          Expanded(
            flex: 2, // Chiếm 2 phần không gian
            child: Container(
              padding: const EdgeInsets.all(10.0),
              width: double.infinity, // Chiếm toàn bộ chiều rộng
              color: Colors.grey[200], // Màu nền xám nhạt
              child: SingleChildScrollView( // Cho phép cuộn nếu nội dung dài
                child: Text(
                  recognizedText.isEmpty
                      ? 'Chụp ảnh để nhận diện thủ ngữ' // Text hướng dẫn khi chưa có kết quả
                      : 'Kết quả:\n' + recognizedText, // Hiển thị kết quả, thêm "Kết quả:\n"
                  style: TextStyle(fontSize: 18.0, fontWeight: FontWeight.bold),
                  textAlign: TextAlign.center,
                ),
              ),
            ),
          ),

           // Nút Xóa kết quả
           Padding(
             padding: const EdgeInsets.symmetric(vertical: 10.0),
             child: ElevatedButton(
               // Chỉ cho phép ấn khi có kết quả để xóa và không đang xử lý
               onPressed: recognizedText.isNotEmpty && !isProcessing ? clearResults : null,
               child: const Text('Xóa kết quả'),
             ),
           ),
        ],
      ),
    );
  }
}