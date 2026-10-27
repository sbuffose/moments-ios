// ContactPickerView.swift
// SwiftUI wrapper for CNContactPickerViewController

import SwiftUI
import ContactsUI

struct ContactPickerView: UIViewControllerRepresentable {
    @Environment(\.dismiss) private var dismiss
    let onSelect: (String) -> Void
    
    func makeUIViewController(context: Context) -> CNContactPickerViewController {
        let picker = CNContactPickerViewController()
        picker.delegate = context.coordinator
        picker.predicateForEnablingContact = NSPredicate(format: "givenName.length > 0 OR familyName.length > 0")
        return picker
    }
    
    func updateUIViewController(_ uiViewController: CNContactPickerViewController, context: Context) {}
    
    func makeCoordinator() -> Coordinator {
        Coordinator(self)
    }
    
    class Coordinator: NSObject, CNContactPickerDelegate {
        let parent: ContactPickerView
        
        init(_ parent: ContactPickerView) {
            self.parent = parent
        }
        
        func contactPicker(_ picker: CNContactPickerViewController, didSelect contact: CNContact) {
            let name = [contact.givenName, contact.familyName]
                .filter { !$0.isEmpty }
                .joined(separator: " ")
            
            if !name.isEmpty {
                parent.onSelect(name)
            }
            parent.dismiss()
        }
        
        func contactPickerDidCancel(_ picker: CNContactPickerViewController) {
            parent.dismiss()
        }
    }
}

struct ContactPickerButton: View {
    let onNameSelected: (String) -> Void
    @State private var showPicker = false
    
    var body: some View {
        Button {
            MomentsHaptics.light()
            showPicker = true
        } label: {
            HStack {
                Image(systemName: "person.crop.circle.badge.plus")
                Text("cataloging_pick_from_contacts")
            }
            .font(MomentsTypography.bodyMedium)
            .foregroundStyle(MomentsColors.accent)
            .padding(.horizontal, MomentsSpacing.md)
            .padding(.vertical, MomentsSpacing.sm)
            .background(MomentsColors.accent.opacity(0.1))
            .cornerRadius(12)
        }
        .sheet(isPresented: $showPicker) {
            ContactPickerView(onSelect: onNameSelected)
        }
    }
}
