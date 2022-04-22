//
//  ConsoleView.swift
//  sshtest
//
//  Created by rei8 on 2022/04/16.
//

import SwiftUI

struct ConsoleView: View {
    @Binding var isActive: Bool
    @ObservedObject var handler: stdHandlers
    @ObservedObject var term: TerminalScreen
    
    @State var remainStdIn: [UInt8] = []

    @State var textInputMode = false
    @State var textInput = ""
    
    @State var screenView: AnyView = AnyView(EmptyView())
    
    
    func stdout(_ data: ArraySlice<UInt8>) {
        if data.isEmpty, !term.screenBuffer.isEmpty {
            DispatchQueue.main.async {
                screenView = AnyView(term.renderScreen())
            }
        }
        else {
            DispatchQueue.main.async {
                term.screenBuffer += data
            }
        }
    }
    
    func stdin()->[UInt8] {
        DispatchQueue.main.sync {
            let value: [UInt8] = remainStdIn
            remainStdIn = []
            return value
        }
    }
    
    func inHndler(_ data: [UInt8]) {
        print(data)
        remainStdIn += data
    }
    
    
    var body: some View {
        VStack {
            HStack {
                Text(term.windowTitle).font(.headline.monospaced())
                Spacer()
            }
            GeometryReader { geometry in
                screenView
                    .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
                    .onAppear() {
                        print("geometry:\(geometry.size.width):\(geometry.size.height)")
                        let newSize = term.screen.setSize(size: geometry.size)
                        handler.screeSizeChane?(newSize.width, newSize.height)
                    }
                    .onChange(of: geometry.size, perform: { newValue in
                        print("geometry onChange:\(newValue.width):\(newValue.height)")
                        let newSize = term.screen.setSize(size: newValue)
                        handler.screeSizeChane?(newSize.width, newSize.height)
                    })
                    .onChange(of: term.screen.fontSize) { newValue in
                        print("fontsize:\(term.screen.fontSize)")
                        let newSize = term.screen.setSize(size: geometry.size)
                        handler.screeSizeChane?(newSize.width, newSize.height)
                    }
            }
        }
        .background(InvisibleTextViewWrapper(isFirstResponder: term.$screen.showingKeyboad, textInputMode: $textInputMode, console: term.screen))
        .onTapGesture(count: 2) {
            if term.screen.showingKeyboad {
                inHndler([9])
            }
        }
        .onTapGesture(count: 1) {
            term.screen.showingKeyboad.toggle()
        }
        .onAppear() {
            handler.stdOutFcn = stdout(_:)
            handler.stdInFcn = stdin
            term.screen.stdinHandler = inHndler(_:)
        }
        .onChange(of: textInputMode) { value in
            if value {
                term.screen.showingKeyboad = false
                textInput = ""
            }
        }
        .onChange(of: isActive) { value in
            if !value {
                term.screen.showingKeyboad = false
                textInputMode = false
            }
        }
        .sheet(isPresented: $textInputMode) {
            Group {
                Text("Input insert text")
                TextEditor(text: $textInput)
                    .cornerRadius(16)
                    .overlay(
                      RoundedRectangle(cornerRadius: 16)
                      .stroke(.green, lineWidth: 4)
                    )
                    .padding()
                HStack {
                    Spacer()
                    Button("Done") {
                        inHndler(Array(textInput.data(using: .utf8)!))
                        textInputMode = false
                        term.screen.showingKeyboad = true
                    }
                    Spacer()
                    Button("Cancel", role: .cancel, action: {
                        textInputMode = false
                        term.screen.showingKeyboad = true
                    })
                    Spacer()
                }
                Spacer()
            }
            .padding()
        }
    }
}

struct ConsoleView_Previews: PreviewProvider {
    @State static var isActive = false
    @StateObject static var handler = stdHandlers()
    @StateObject static var term = TerminalScreen()

    static var previews: some View {
        ConsoleView(isActive: $isActive, handler: handler, term: term)
    }
}
