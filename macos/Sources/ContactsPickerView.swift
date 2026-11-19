import SwiftUI

struct ContactsPickerView: View {
    @ObservedObject var contacts: ContactsStore
    var onSelect: (String) -> Void

    @Environment(\.dismiss) private var dismiss
    @State private var query = ""
    @State private var editingContact: Contact?

    private var filtered: [Contact] {
        contacts.search(query)
    }

    var body: some View {
        VStack(spacing: 0) {
            HStack(spacing: 12) {
                ZStack {
                    Circle().fill(Palette.blueSoft)
                    Image(systemName: "person.2.fill")
                        .font(.system(size: 13, weight: .semibold))
                        .foregroundStyle(Palette.blue)
                }
                .frame(width: 34, height: 34)

                VStack(alignment: .leading, spacing: 2) {
                    Text("通讯录")
                        .font(.system(size: 17, weight: .bold, design: .rounded))
                        .foregroundStyle(Palette.ink)
                    Text("发送过的临时邮箱会自动保存")
                        .font(.system(size: 10.5))
                        .foregroundStyle(Palette.secondary)
                }

                Spacer()

                Button {
                    dismiss()
                } label: {
                    Image(systemName: "xmark")
                        .font(.system(size: 11, weight: .semibold))
                        .foregroundStyle(Palette.secondary)
                        .frame(width: 28, height: 28)
                        .background(Circle().fill(Color.white.opacity(0.8)))
                }
                .buttonStyle(.plain)
            }
            .padding(.horizontal, 20)
            .padding(.top, 18)
            .padding(.bottom, 12)

            HStack(spacing: 8) {
                Image(systemName: "magnifyingglass")
                    .font(.system(size: 11, weight: .medium))
                    .foregroundStyle(Palette.tertiary)
                TextField("搜索邮箱地址", text: $query)
                    .textFieldStyle(.plain)
                    .font(.system(size: 12.5))
                if !query.isEmpty {
                    Button {
                        query = ""
                    } label: {
                        Image(systemName: "xmark.circle.fill")
                            .font(.system(size: 11))
                            .foregroundStyle(Palette.tertiary)
                    }
                    .buttonStyle(.plain)
                }
            }
            .padding(.horizontal, 11)
            .frame(height: 36)
            .background(
                RoundedRectangle(cornerRadius: 10, style: .continuous)
                    .fill(Color.white)
            )
            .overlay(
                RoundedRectangle(cornerRadius: 10, style: .continuous)
                    .stroke(Palette.softBorder, lineWidth: 1)
            )
            .padding(.horizontal, 20)

            Divider()
                .overlay(Palette.softBorder)
                .padding(.top, 14)

            if filtered.isEmpty {
                VStack(spacing: 8) {
                    Image(systemName: query.isEmpty ? "person.crop.circle.badge.plus" : "magnifyingglass")
                        .font(.system(size: 30, weight: .light))
                        .foregroundStyle(Palette.tertiary)
                    Text(query.isEmpty ? "通讯录还是空的" : "没有找到匹配的邮箱")
                        .font(.system(size: 13, weight: .semibold))
                        .foregroundStyle(Palette.secondary)
                    Text(query.isEmpty ? "给临时邮箱发送一次后，会自动出现在这里。" : "换个关键词试试。")
                        .font(.system(size: 11))
                        .foregroundStyle(Palette.tertiary)
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                ScrollView(.vertical, showsIndicators: true) {
                    LazyVStack(spacing: 0) {
                        ForEach(filtered) { contact in
                            contactRow(contact)
                            Divider()
                                .overlay(Palette.softBorder)
                                .padding(.leading, 56)
                        }
                    }
                    .padding(.horizontal, 8)
                }
            }
        }
        .frame(width: 460, height: 500)
        .background(Palette.background)
        .sheet(item: $editingContact) { contact in
            ContactNameEditor(contact: contact, contacts: contacts)
        }
    }

    private func contactRow(_ contact: Contact) -> some View {
        HStack(spacing: 4) {
            Button {
                onSelect(contact.email)
                dismiss()
            } label: {
                HStack(spacing: 11) {
                    ZStack {
                        Circle()
                            .fill(Palette.blueSoft)
                        Text(String(contact.displayName.prefix(1)).uppercased())
                            .font(.system(size: 12, weight: .bold, design: .rounded))
                            .foregroundStyle(Palette.blue)
                    }
                    .frame(width: 32, height: 32)

                    VStack(alignment: .leading, spacing: 2) {
                        Text(contact.displayName)
                            .font(.system(size: 12.5, weight: .semibold))
                            .foregroundStyle(Palette.ink)
                            .lineLimit(1)
                            .truncationMode(.middle)
                        if contact.hasDisplayName {
                            Text(contact.email)
                                .font(.system(size: 10.5))
                                .foregroundStyle(Palette.secondary)
                                .lineLimit(1)
                                .truncationMode(.middle)
                        }
                        Text("使用 \(contact.useCount) 次 · \(relativeDate(contact.lastUsed))")
                            .font(.system(size: 10))
                            .foregroundStyle(Palette.tertiary)
                    }

                    Spacer(minLength: 4)

                    Image(systemName: "arrow.up.left.circle.fill")
                        .font(.system(size: 15))
                        .foregroundStyle(Palette.blue.opacity(0.7))
                }
                .padding(.horizontal, 8)
                .padding(.vertical, 9)
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)

            Button {
                editingContact = contact
            } label: {
                Image(systemName: "pencil")
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundStyle(Palette.tertiary)
                    .frame(width: 28, height: 28)
                    .background(Circle().fill(Color.white.opacity(0.8)))
            }
            .buttonStyle(.plain)
            .help("编辑备注名字")
        }
        .contextMenu {
            Button("编辑备注名字") {
                editingContact = contact
            }
            Button("删除", role: .destructive) {
                contacts.remove(contact)
            }
        }
    }

    private func relativeDate(_ date: Date) -> String {
        let formatter = RelativeDateTimeFormatter()
        formatter.locale = Locale(identifier: "zh_CN")
        formatter.unitsStyle = .short
        return formatter.localizedString(for: date, relativeTo: Date())
    }
}
