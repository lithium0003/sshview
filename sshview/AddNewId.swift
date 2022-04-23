//
//  AddNewId.swift
//  sshtest
//
//  Created by rei8 on 2022/04/15.
//

import SwiftUI
import libssh

struct AddNewId: View {
    @EnvironmentObject var userProfile: UserProfile
    @Binding var newId: UUID

    @State private var showSheet = false
    let keytype = ["rsa","ecdsa","ed25519"]
    @State private var selectionKeytype = "ed25519"
    @State private var keybit = 256
    
    @State private var idname = ""
    @State private var username = ""
    @State private var passphease = ""
    @State private var privateKey: String = """
    -----BEGIN OPENSSH PRIVATE KEY-----
    (base64 encoded private key paste here)
    -----END OPENSSH PRIVATE KEY-----
    """
    @State private var publicKey = ""
    
    @Binding var isShowSubView: Bool
    @State private var showingExporter = false
    @State private var pubFile = TextFile()
    @State private var isImporting = false
    
    var body: some View {
        VStack {
            Spacer()
            TextField("Tag", text: $idname)
                .textFieldStyle(.roundedBorder)
                .keyboardType(.default)
            TextField("Username", text: $username)
                .textFieldStyle(.roundedBorder)
                .keyboardType(.alphabet)
                .autocapitalization(.none)
                .disableAutocorrection(true)
            Button(action: {
                self.showSheet.toggle()
            }, label: {
                Text("Generate new keypair")
            }).sheet(isPresented: self.$showSheet, content: {
                VStack {
                    Text("Generate new keypair")
                    Picker("keytype", selection: $selectionKeytype) {
                        ForEach(keytype, id: \.self) { key in
                            Text(key)
                        }
                    }
                    .pickerStyle(.segmented)
                    .onChange(of: selectionKeytype) { newValue in
                        switch newValue {
                        case "rsa":
                            keybit = 4096
                        case "ecdsa":
                            keybit = 521
                        case "ed25519":
                            keybit = 256
                        default:
                            break
                        }
                    }
                    switch selectionKeytype {
                    case "rsa":
                        Picker("keybits", selection: $keybit) {
                            Text("2048").tag(2048)
                            Text("4096").tag(4096)
                        }
                        .pickerStyle(.segmented)
                    case "ecdsa":
                        Picker("keybits", selection: $keybit) {
                            Text("256").tag(256)
                            Text("384").tag(384)
                            Text("521").tag(521)
                        }
                        .pickerStyle(.segmented)
                    default:
                        EmptyView()
                    }
                    SecureField("private key passphrease", text: $passphease)
                        .textFieldStyle(.roundedBorder)
                        .keyboardType(.alphabet)
                        .autocapitalization(.none)

                    Button(action: {
                        ssh_init()
                        defer {
                            ssh_finalize()
                        }
                        
                        var pri: UnsafeMutablePointer<CChar>?
                        var pub: UnsafeMutablePointer<CChar>?
                        var newkey: ssh_key?
                        
                        let keytype: ssh_keytypes_e
                        switch selectionKeytype {
                        case "rsa":
                            keytype = SSH_KEYTYPE_RSA
                        case "ecdsa":
                            keytype = SSH_KEYTYPE_ECDSA
                        case "ed25519":
                            keytype = SSH_KEYTYPE_ED25519
                        default:
                            return
                        }
                        guard ssh_pki_generate(keytype, Int32(keybit), &newkey) == SSH_OK else {
                            return
                        }
                        defer {
                            ssh_key_free(newkey)
                        }
                        var pp = passphease.cString(using: .utf8)
                        if passphease.isEmpty {
                            pp = nil
                        }
                        
                        ssh_pki_export_privkey_base64(newkey, pp, nil, nil, &pri)
                        guard let prikey = pri else {
                            return
                        }
                        privateKey = String(cString: prikey)
                        
                        ssh_pki_export_pubkey_base64(newkey, &pub)
                        guard let pubkey = pub else {
                            return
                        }
                        var sshkeystr = String(cString: ssh_key_type_to_char(keytype))
                        if keytype == SSH_KEYTYPE_ECDSA {
                            sshkeystr = String(cString: ssh_pki_key_ecdsa_name(newkey))
                        }
                        publicKey = sshkeystr + " " + String(cString: pubkey)
                    }) {
                        Text("Generate")
                    }
                    
                    ScrollView {
                        Text(publicKey)
                            .textSelection(.enabled)
                    }
                    HStack {
                        Spacer()
                        Button(action: {
                            UIPasteboard.general.string = publicKey
                        }) {
                            Image(systemName: "doc.on.clipboard")
                                .font(.largeTitle)
                        }
                        Spacer()
                        Button(action: {
                            pubFile.text = publicKey
                            showingExporter = true
                        }) {
                            Image(systemName: "arrow.down.doc")
                                .font(.largeTitle)
                        }
                        .fileExporter(isPresented: $showingExporter, document: pubFile, contentType: .plainText, defaultFilename: "newkey") { result in
                            switch result {
                             case .success(let url):
                                 print("Saved to \(url)")
                             case .failure(let error):
                                 print(error.localizedDescription)
                             }
                        }
                        Spacer()
                        Button(action: {
                            self.showSheet = false
                        }) {
                            Text("Done")
                        }
                        Spacer()
                    }
                    .padding()
                    .opacity(publicKey.isEmpty ? 0 : 1)
                }
                .padding()
            })
            HStack {
                Text("or, paste private key")
                Button(action: {
                    isImporting = true
                }) {
                    Image(systemName: "doc.text")
                        .font(.title)
                }
                .fileImporter(isPresented: $isImporting, allowedContentTypes: [.text]) { result in
                    if case .success = result {
                        do {
                            let url = try result.get()
                            guard url.startAccessingSecurityScopedResource() else {
                                return
                            }
                            defer {
                                url.stopAccessingSecurityScopedResource()
                            }
                            privateKey = try String(contentsOf: url)
                        }
                        catch {
                            print(error)
                        }
                    }
                }
            }
            TextEditor(text: $privateKey)
                .keyboardType(.alphabet)
                .autocapitalization(.none)
                .disableAutocorrection(true)
                .overlay(
                    RoundedRectangle(cornerRadius: 5)
                        .stroke(Color.gray, lineWidth: 1)
                )
            SecureField("private key passphrease", text: $passphease)
                .textFieldStyle(.roundedBorder)
                .keyboardType(.alphabet)
                .autocapitalization(.none)
                .disableAutocorrection(true)
            Spacer()
            Button(action: {
                guard !idname.isEmpty else {
                    return
                }
                guard !username.isEmpty else {
                    return
                }
                guard !privateKey.isEmpty else {
                    return
                }
                let newuser = UserIdItem(title: idname, userName: username, b64_prrvateKey: privateKey, passphrease: passphease)
                newId = newuser.id
                userProfile.userid.append(newuser)
                
                isShowSubView = false
            }) {
                Text("Done")
                    .font(.title)
            }
            Spacer()
        }
        .padding()
    }
}

struct AddNewId_Previews: PreviewProvider {
    @State static var newid = UUID()
    @State static var isShowSubView = false
    
    static var previews: some View {
        AddNewId(newId: $newid, isShowSubView: $isShowSubView)
    }
}
