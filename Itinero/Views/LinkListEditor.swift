import SwiftUI

/// Rows for a list of web links, with add + swipe-to-delete. Use inside a Form/List `Section`.
struct LinkListEditor: View {
    @Binding var links: [String]
    @State private var newLink = ""

    var body: some View {
        ForEach(links, id: \.self) { link in
            Text(link.replacingOccurrences(of: "https://", with: "")).font(.subheadline).lineLimit(1)
        }
        .onDelete { links.remove(atOffsets: $0) }
        HStack {
            TextField("Add a link (tickets, website…)", text: $newLink)
                .keyboardType(.URL).textInputAutocapitalization(.never).autocorrectionDisabled()
                .onSubmit(add)
            Button("Add", action: add).disabled(LinkNormalizer.normalize(newLink) == nil)
        }
    }

    private func add() {
        guard let url = LinkNormalizer.normalize(newLink), !links.contains(url.absoluteString) else { return }
        links.append(url.absoluteString)
        newLink = ""
    }
}
