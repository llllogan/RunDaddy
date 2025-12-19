import SwiftUI
import UIKit

struct TextFieldAlert: UIViewControllerRepresentable {
    @Binding var isPresented: Bool
    @Binding var text: String
    let title: String
    let message: String?
    let confirmTitle: String
    let cancelTitle: String
    let secondaryTitle: String?
    let secondaryStyle: UIAlertAction.Style
    let keyboardType: UIKeyboardType
    let allowedCharacterSet: CharacterSet?
    let onConfirm: () -> Void
    let onSecondary: (() -> Void)?
    let onCancel: () -> Void
    
    func makeCoordinator() -> Coordinator {
        Coordinator(allowedCharacterSet: allowedCharacterSet) { newValue in
            guard let allowedCharacterSet else {
                DispatchQueue.main.async {
                    text = newValue
                }
                return
            }

            let filteredScalars = newValue.unicodeScalars.filter { allowedCharacterSet.contains($0) }
            let filtered = String(String.UnicodeScalarView(filteredScalars))
            DispatchQueue.main.async {
                text = filtered
            }
        }
    }
    
    func makeUIViewController(context: Context) -> UIViewController {
        UIViewController()
    }
    
    func updateUIViewController(_ uiViewController: UIViewController, context: Context) {
        if isPresented && context.coordinator.alert == nil {
            let alert = UIAlertController(title: title, message: message, preferredStyle: .alert)
            alert.addTextField { field in
                field.keyboardType = keyboardType
                field.clearButtonMode = .whileEditing
                field.text = text
                field.placeholder = "Enter value"
                field.addTarget(context.coordinator, action: #selector(Coordinator.textDidChange(_:)), for: .editingChanged)
            }
            
            let cancelAction = UIAlertAction(title: cancelTitle, style: .cancel) { _ in
                text = alert.textFields?.first?.text ?? text
                isPresented = false
                context.coordinator.alert = nil
                onCancel()
            }
            
            let confirmAction = UIAlertAction(title: confirmTitle, style: .default) { _ in
                text = alert.textFields?.first?.text ?? text
                isPresented = false
                context.coordinator.alert = nil
                onConfirm()
            }

            if let secondaryTitle, let onSecondary {
                let secondaryAction = UIAlertAction(title: secondaryTitle, style: secondaryStyle) { _ in
                    isPresented = false
                    context.coordinator.alert = nil
                    onSecondary()
                }
                alert.addAction(secondaryAction)
            }
            
            alert.addAction(cancelAction)
            alert.addAction(confirmAction)
            
            uiViewController.present(alert, animated: true)
            context.coordinator.alert = alert
        } else if !isPresented, let alert = context.coordinator.alert {
            alert.dismiss(animated: true)
            context.coordinator.alert = nil
        } else if let alert = context.coordinator.alert {
            if alert.message != message {
                alert.message = message
            }
            if let textField = alert.textFields?.first, textField.text != text {
                textField.text = text
            }
        }
    }

    class Coordinator: NSObject {
        var alert: UIAlertController?
        private let allowedCharacterSet: CharacterSet?
        private let onTextChange: (String) -> Void
        
        init(allowedCharacterSet: CharacterSet?, onTextChange: @escaping (String) -> Void) {
            self.allowedCharacterSet = allowedCharacterSet
            self.onTextChange = onTextChange
        }
        
        @objc
        func textDidChange(_ sender: UITextField) {
            let current = sender.text ?? ""
            if let allowedCharacterSet {
                let filteredScalars = current.unicodeScalars.filter { allowedCharacterSet.contains($0) }
                let filtered = String(String.UnicodeScalarView(filteredScalars))
                if filtered != current {
                    sender.text = filtered
                }
                onTextChange(filtered)
            } else {
                onTextChange(current)
            }
        }
    }
}

struct TextFieldAlertModifier: ViewModifier {
    @Binding var isPresented: Bool
    @Binding var text: String
    let title: String
    let message: String?
    let confirmTitle: String
    let cancelTitle: String
    let secondaryTitle: String?
    let secondaryStyle: UIAlertAction.Style
    let keyboardType: UIKeyboardType
    let allowedCharacterSet: CharacterSet?
    let onConfirm: () -> Void
    let onSecondary: (() -> Void)?
    let onCancel: () -> Void
    
    func body(content: Content) -> some View {
        content
            .background(
                TextFieldAlert(
                    isPresented: $isPresented,
                    text: $text,
                    title: title,
                    message: message,
                    confirmTitle: confirmTitle,
                    cancelTitle: cancelTitle,
                    secondaryTitle: secondaryTitle,
                    secondaryStyle: secondaryStyle,
                    keyboardType: keyboardType,
                    allowedCharacterSet: allowedCharacterSet,
                    onConfirm: onConfirm,
                    onSecondary: onSecondary,
                    onCancel: onCancel
                )
            )
    }
}

extension View {
    func textFieldAlert(
        isPresented: Binding<Bool>,
        text: Binding<String>,
        title: String,
        message: String?,
        confirmTitle: String,
        cancelTitle: String,
        secondaryTitle: String? = nil,
        secondaryStyle: UIAlertAction.Style = .default,
        keyboardType: UIKeyboardType,
        allowedCharacterSet: CharacterSet? = .decimalDigits,
        onConfirm: @escaping () -> Void,
        onSecondary: (() -> Void)? = nil,
        onCancel: @escaping () -> Void
    ) -> some View {
        modifier(
            TextFieldAlertModifier(
                isPresented: isPresented,
                text: text,
                title: title,
                message: message,
                confirmTitle: confirmTitle,
                cancelTitle: cancelTitle,
                secondaryTitle: secondaryTitle,
                secondaryStyle: secondaryStyle,
                keyboardType: keyboardType,
                allowedCharacterSet: allowedCharacterSet,
                onConfirm: onConfirm,
                onSecondary: onSecondary,
                onCancel: onCancel
            )
        )
    }
}
