//
//  QRCodeView.swift
//  PickAgent
//
//  Created by ChatGPT on 11/8/2025.
//

import SwiftUI
import CoreImage

struct QRCodeView: View {
    let code: String
    let size: CGFloat
    
    var body: some View {
        Group {
            if let qrImage = generateQRCode(from: code) {
                Image(uiImage: UIImage(ciImage: qrImage))
                    .interpolation(.none)
                    .resizable()
                    .scaledToFit()
                    .frame(width: size, height: size)
            } else {
                Rectangle()
                    .fill(Color.gray.opacity(0.3))
                    .frame(width: size, height: size)
                    .overlay(
                        Text("QR Code")
                            .foregroundColor(.gray)
                    )
            }
        }
    }
    
    private func generateQRCode(from string: String) -> CIImage? {
        let data = Data(string.utf8)
        let filter = CIFilter(name: "CIQRCodeGenerator")
        filter?.setValue(data, forKey: "inputMessage")
        filter?.setValue("H", forKey: "inputCorrectionLevel")
        
        return filter?.outputImage
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
