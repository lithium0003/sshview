//
//  UserIdDetail.swift
//  sshtest
//
//  Created by rei8 on 2022/04/15.
//

import SwiftUI
import UniformTypeIdentifiers
import libssh

struct TextFile: FileDocument {
    static var readableContentTypes = [UTType.plainText]

    var text = ""

    init(initialText: String = "") {
        text = initialText
    }

    init(configuration: ReadConfiguration) throws {
        if let data = configuration.file.regularFileContents {
            text = String(decoding: data, as: UTF8.self)
        }
    }

    func fileWrapper(configuration: WriteConfiguration) throws -> FileWrapper {
        let data = Data(text.utf8)
        return FileWrapper(regularFileWithContents: data)
    }
}

struct UserIdDetail: View {
    var idItem: UserIdItem
    @State private var showingExporter = false
    @State private var pubFile = TextFile()
    
    func getPubKey() -> String {
        let b64_prikey = idItem.b64_prrvateKey
        let passphrase = idItem.passphrease
        
        var prikey: ssh_key!
        var pubkey: ssh_key!

        guard ssh_pki_import_privkey_base64(b64_prikey, passphrase, nil, nil, &prikey) == SSH_OK, prikey != nil else {
            return ""
        }
        defer {
            ssh_key_free(prikey)
        }
        
        guard ssh_pki_export_privkey_to_pubkey(prikey, &pubkey) == SSH_OK else {
            return ""
        }
        defer {
            ssh_key_free(pubkey)
        }

        var pub: UnsafeMutablePointer<CChar>?
        ssh_pki_export_pubkey_base64(pubkey, &pub)
        guard let pubkey_b64 = pub else {
            return ""
        }

        let sshkeystr = String(cString: ssh_key_type_to_char(ssh_key_type(pubkey)))

        return sshkeystr + " " + String(cString: pubkey_b64)
    }
    
    var body: some View {
        ScrollView {
            VStack(alignment: .leading) {
                Text(idItem.title)
                    .font(.title)
                    .foregroundColor(.primary)

                Text(idItem.userName)
                Text(idItem.b64_prrvateKey)
                    .textSelection(.enabled)

                Text(getPubKey())
                    .textSelection(.enabled)
                Spacer()
                HStack {
                    Spacer()
                    Button(action: {
                        UIPasteboard.general.string = getPubKey()
                    }) {
                        Image(systemName: "doc.on.clipboard")
                            .font(.largeTitle)
                    }
                    Spacer()
                    Button(action: {
                        pubFile.text = getPubKey()
                        showingExporter = true
                    }) {
                        Image(systemName: "arrow.down.doc")
                            .font(.largeTitle)
                    }
                    .fileExporter(isPresented: $showingExporter, document: pubFile, contentType: .plainText, defaultFilename: "\(idItem.title)") { result in
                        switch result {
                         case .success(let url):
                             print("Saved to \(url)")
                         case .failure(let error):
                             print(error.localizedDescription)
                         }
                    }
                    Spacer()
                }
                .padding()
            }
            .padding()
        }
    }
}

struct UserIdDetail_Previews: PreviewProvider {
    static var previews: some View {
        UserIdDetail(idItem: UserIdItem(title: "test"))
    }
}
