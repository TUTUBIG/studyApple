//
//  ImagePickerView.swift
//  studyApple
//
//  Created by Alvin liu on 2024/4/25.
//

import SwiftUI

struct ImagePickerView: View {
    @State var present = false
    @State var progress: Double = 0
    var body: some View {
        Text("Progress \(progress)")
        Button("click") {
            present = true
        }
        .sheet(isPresented: $present, content: {
            ImagePickerUIKit(progress: $progress, present: $present)
        })
    }
}

fileprivate struct ImagePickerUIKit: UIViewControllerRepresentable {
    @Binding var progress: Double
    @Binding var present: Bool
    func makeUIViewController(context: Context) -> some UIViewController {
        let picker = UIImagePickerController()
        if let mediaTypes = UIImagePickerController.availableMediaTypes(for: .camera) {
            picker.mediaTypes = mediaTypes
        }
        picker.sourceType = .camera
        picker.videoQuality = .typeHigh
        picker.delegate = context.coordinator
        return picker
    }
    func updateUIViewController(_ uiViewController: UIViewControllerType, context: Context) {
        
    }
    func makeCoordinator() -> Coordinator {
        return Coordinator(parent: self)
    }
    
    class Coordinator: NSObject, UIImagePickerControllerDelegate,UINavigationControllerDelegate {
        var parent: ImagePickerUIKit
        
        init(parent: ImagePickerUIKit) {
            self.parent = parent
        }
        
        func imagePickerController(_ picker: UIImagePickerController, didFinishPickingMediaWithInfo info: [UIImagePickerController.InfoKey : Any]) {
            if let videoURL = info[.mediaURL] as? URL {
                print("selected video url \(videoURL.absoluteString)")
                parent.uploadVideoMultiplePart(videoURL: videoURL, chunkSize: 6 * 1024 * 1024) { progress in
                    print("upload \(progress)")
                    self.parent.progress = progress
                }
            } else if let imageURL = info[.imageURL] as? URL {
                print("selected image url \(imageURL.absoluteString)")
                parent.uploadVideoMultiplePart(videoURL: imageURL, chunkSize: 6 * 1024 * 1024) { progress in
                    print("upload \(progress)")
                }
            }
            parent.present = false
        }
        func imagePickerControllerDidCancel(_ picker: UIImagePickerController) {
            parent.present = false
        }
    }
    
    func uploadVideo(videoURL: URL) {
        let url = URL(string: "")!
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        let task = URLSession.shared.uploadTask(with: request, fromFile: videoURL) {data,response,error in
            if error != nil {
                print(error!.localizedDescription)
                return
            }
            guard let httpResponse = response as? HTTPURLResponse, httpResponse.statusCode == 200 else {
                print("response error")
                return
            }
            
            if let data = data {
                let dataS = String(data: data , encoding: .utf8)
                print("video updated successfully \(dataS ?? "")")
            }
        }
        task.resume()
    }
    func uploadVideoMultiplePart(videoURL: URL,chunkSize: Int, updateProcess: @escaping(_ progress: Double) -> Void) {
        Task {
            do {
                let uploadId = try await createR2(name: videoURL.lastPathComponent)
                print("create r2 success uploadId \(uploadId)")
                
//                let attributes = try FileManager.default.attributesOfItem(atPath: videoURL.absoluteString)
//                guard let fileSize = attributes[.size] as? Int else {
//                    fatalError("wierd file size")
//                }
//                let chuncks = fileSize / chunkSize + 1
//                
                let file = try FileHandle(forReadingFrom: videoURL)
                
                var i = 1
                var completeParts = [MpuUpdateResponse]()
                while true {
                    do {
                        if let dataChunk = try file.read(upToCount: chunkSize) {
                            if dataChunk.isEmpty {
                                break
                            } else {
                                let completePart = try await putDataToR2(name: videoURL.lastPathComponent,data: dataChunk, uploadId: uploadId, partNumber: "\(i)")
                                completeParts.append(completePart)
                                // updateProcess(Double(i))
                                i += 1
                            }
                        } else {
                            break
                        }
                    } catch {
                        print("read file error \(error)")
                        break
                    }
                }
                let remote = try await finishR2(name: videoURL.lastPathComponent, uploadId: uploadId,completeParts: completeParts)
                print("upload success R2 \(remote.r2) HLS \(remote.hls)")
                updateProcess(1)
                try file.close()
            } catch {
                print("upload file failed \(error)")
            }
        }
        
        @Sendable func putDataToR2(name: String,data: Data,uploadId: String,partNumber: String) async throws -> MpuUpdateResponse {
            var url = URL(string: "https://first-demo.bigtutu.workers.dev/\(name)")!
            url.append(queryItems: [URLQueryItem(name: "action", value: "mpu-uploadpart"),URLQueryItem(name: "uploadId", value: uploadId),URLQueryItem(name: "partNumber", value: partNumber)])
            var request = URLRequest(url: url)
            request.httpMethod = "PUT"
            do {
                let (data,response) = try await URLSession.shared.upload(for: request, from: data)
                guard let httpResponse = response as? HTTPURLResponse, httpResponse.statusCode == 200 else {
                    throw URLError(.badServerResponse, userInfo: ["error code": "invalid http response"])
                }
                print("upload \(partNumber) success \(String(data: data, encoding: .utf8) ?? "")")
                do {
                    let response = try JSONDecoder().decode(MpuUpdateResponse.self, from: data)
                    return response
                } catch {
                    throw error
                }
            } catch {
                throw error
            }
        }
        
        @Sendable func createR2(name: String) async throws -> String  {
            var url = URL(string: "https://first-demo.bigtutu.workers.dev/\(name)")!
            url.append(queryItems: [URLQueryItem(name: "action", value: "mpu-create")])
            var request = URLRequest(url: url)
            request.httpMethod = "POST"
            
            do {
                let (data,response) = try await URLSession.shared.data(for: request)
                guard let httpResponse = response as? HTTPURLResponse, httpResponse.statusCode == 200 else {
                    throw URLError(.badServerResponse, userInfo: ["error code": "invalid http response"])
                }
                do {
                    let response = try JSONDecoder().decode(MpuCreateResponse.self, from: data)
                    return response.uploadId
                } catch {
                    throw error
                }
            } catch {
                throw error
            }
        }
        
        @Sendable func finishR2(name: String,uploadId: String,completeParts: [MpuUpdateResponse]) async throws -> MapCompeleteResponse  {
            var url = URL(string: "https://first-demo.bigtutu.workers.dev/\(name)")!
            url.append(queryItems: [URLQueryItem(name: "action", value: "mpu-complete"),URLQueryItem(name: "uploadId", value: uploadId)])
            var request = URLRequest(url: url)
            request.httpMethod = "POST"
            
            do {
                let compeleteRequest = MapCompeleteRequest(parts: completeParts)
                let postData = try JSONEncoder().encode(compeleteRequest)
                let (data,response) = try await URLSession.shared.upload(for: request, from: postData)
                guard let httpResponse = response as? HTTPURLResponse else {
                    fatalError("wierd")
                }
                if httpResponse.statusCode != 200 {
                    throw URLError(.badServerResponse, userInfo: ["code" : httpResponse.statusCode,"text" : String(data:data,encoding: .utf8) ?? ""])
                }
                do {
                    let response = try JSONDecoder().decode(MapCompeleteResponse.self, from: data)
                    return response
                } catch {
                    throw error
                }
            } catch {
                throw error
            }
        }
    }
}

struct MpuCreateResponse: Decodable {
    let key: String
    let uploadId: String
}

struct MpuUpdateResponse: Codable {
    let partNumber: Int
    let etag: String
}

struct MapCompeleteResponse: Decodable {
    let r2: String
    let hls: String
}
struct MapCompeleteRequest: Encodable {
    let parts: [MpuUpdateResponse]
}

#Preview {
    ImagePickerView()
}
