//
//  QRCodeView.swift
//  PickAgent
//
//  Created by ChatGPT on 11/8/2025.
//

import SwiftUI
import CoreImage
import CoreImage.CIFilterBuiltins

struct QRCodeView: View {
    let code: String
    let size: CGFloat
    
    var body: some View {
        Group {
            if code.isEmpty {
                Rectangle()
                    .fill(Color.red.opacity(0.3))
                    .frame(width: size, height: size)
                    .overlay(
                        Text("Empty Code")
                            .foregroundColor(.red)
                    )
            } else if let qrImage = generateQRCode(from: code) {
                Image(uiImage: qrImage)
                    .interpolation(.none)
                    .resizable()
                    .scaledToFit()
                    .frame(width: size, height: size)
            } else {
                Rectangle()
                    .fill(Color.gray.opacity(0.3))
                    .frame(width: size, height: size)
                    .overlay(
                        VStack {
                            Text("QR Code")
                                .foregroundColor(.gray)
                            Text("Failed to generate")
                                .font(.caption2)
                                .foregroundColor(.red)
                        }
                    )
            }
        }
    }
    
    private func generateQRCode(from string: String) -> UIImage? {
        guard !string.isEmpty else { return nil }
        
        let context = CIContext()
        let filter = CIFilter.qrCodeGenerator()
        filter.message = Data(string.utf8)
        filter.correctionLevel = "H"
        
        guard let qrImage = filter.outputImage else { return nil }
        
        // Scale up the QR code to make it visible and improve quality
        let scale = max(10, size / qrImage.extent.width)
        let transform = CGAffineTransform(scaleX: scale, y: scale)
        let scaledImage = qrImage.transformed(by: transform)
        
        // Convert CIImage to UIImage
        guard let cgImage = context.createCGImage(scaledImage, from: scaledImage.extent) else { return nil }
        
        return UIImage(cgImage: cgImage)
    }
}

#Preview {
    VStack(spacing: 20) {
        QRCodeView(code: "TEST123456789", size: 200)
        Text("Scan this code to join")
            .font(.caption)
            .foregroundColor(.gray)
    }
    .padding()
}
