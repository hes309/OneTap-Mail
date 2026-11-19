import SwiftUI

struct ContactNameEditor: View {
    let contact: Contact
    @ObservedObject var contacts: ContactsStore

    @Environment(\.dismiss) private var dismiss
    @State private var name: String

    init(contact: Contact, contacts: ContactsStore) {
        self.contact = contact
        self.contacts = contacts
        _name = State(initialValue: contact.name ?? "")
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            HStack(spacing: 11) {
                ZStack {
                    Circle().fill(Palette.blueSoft)
                    Image(systemName: "pencil")
                        .font(.system(size: 12, weight: .semibold))
                        .foregroundStyle(Palette.blue)
                }
                .frame(width: 34, height: 34)

                VStack(alignment: .leading, spacing: 2) {
                    Text("编辑联系人备注")
                        .font(.system(size: 16, weight: .bold, design: .rounded))
                        .foregroundStyle(Palette.ink)
                    Text(contact.email)
                        .font(.system(size: 11))
                        .foregroundStyle(Palette.secondary)
                        .lineLimit(1)
                        .truncationMode(.middle)
                }
            }

            VStack(alignment: .leading, spacing: 6) {
                Text("备注名字")
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundStyle(Palette.ink)
                TextField("例如：财务、李经理、供应商", text: $name)
                    .textFieldStyle(.plain)
                    .font(.system(size: 13))
                    .padding(.horizontal, 11)
                    .frame(height: 38)
                    .background(
                        RoundedRectangle(cornerRadius: 10, style: .continuous)
                            .fill(Color.white)
                    )
                    .overlay(
                        RoundedRectangle(cornerRadius: 10, style: .continuous)
                            .stroke(Palette.softBorder, lineWidth: 1)
                    )
                Text("备注只保存在这台 Mac 上，用于快速识别收件人。")
                    .font(.system(size: 10.5))
                    .foregroundStyle(Palette.tertiary)
            }

            HStack {
                Button("取消") { dismiss() }
                    .buttonStyle(SecondaryButtonStyle(compact: true))
                Spacer()
                Button("保存") {
                    contacts.updateName(name, for: contact)
                    dismiss()
                }
                .buttonStyle(PrimaryButtonStyle())
                .keyboardShortcut(.return, modifiers: .command)
            }
        }
        .padding(22)
        .frame(width: 390)
        .background(Palette.background)
    }
}
