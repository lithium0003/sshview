//
//  CommandView.swift
//  sshview
//
//  Created by rei8 on 2022/04/21.
//

import SwiftUI

struct CommandView: View {
    @Binding var isActive: Bool
    @ObservedObject var handler: stdHandlers
    @ObservedObject var term: TerminalScreen
    
    @State var remainStdIn: [UInt8] = []
    @State var isEOF = false
    @Binding var bufferStdOut: [UInt8]

    func stdout(_ data: ArraySlice<UInt8>) {
        if data.isEmpty, !term.screenBuffer.isEmpty {
            DispatchQueue.main.async {
                term.renderScreen()
            }
        }
        else {
            DispatchQueue.main.async {
                term.screenBuffer += data
                bufferStdOut += data
            }
        }
    }
    
    func stdin()->[UInt8]? {
        DispatchQueue.main.sync {
            let value: [UInt8] = remainStdIn
            remainStdIn = []
            if isEOF, value.isEmpty {
                return nil
            }
            return value
        }
    }

    var body: some View {
        VStack {
            HStack {
                Spacer()
                Button(role: .destructive, action: {
                    remainStdIn += [3]
                    isEOF = true
                    DispatchQueue.main.asyncAfter(deadline: .now()+5) {
                        isActive = false
                    }
                }, label: {
                    Image(systemName: "trash")
                    Text("Break")
                })
            }
            GeometryReader { geometry in
                term.screen.makeScreenView()
                    .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
                    .onAppear() {
                        print("geometry:\(geometry.size.width):\(geometry.size.height)")
                        term.screen.clearAll()
                        term.screenBuffer = bufferStdOut
                        _ = term.screen.setSize(size: geometry.size)
                    }
                    .onChange(of: geometry.size, perform: { newValue in
                        print("geometry onChange:\(newValue.width):\(newValue.height)")
                        term.screen.clearAll()
                        term.screenBuffer = bufferStdOut
                        _ = term.screen.setSize(size: newValue)
                    })
                    .onChange(of: term.screen.fontSize) { newValue in
                        print("fontsize:\(term.screen.fontSize)")
                        _ = term.screen.setSize(size: geometry.size)
                    }
                    .onChange(of: term.screen.fontSizeChgDone) { newValue in
                        print("fontsize:\(term.screen.fontSize)")
                        DispatchQueue.main.asyncAfter(deadline: .now()+0.2) {
                            term.screen.clearAll()
                            term.screenBuffer = bufferStdOut
                            _ = term.screen.setSize(size: geometry.size)
                        }
                    }
            }
        }
        .onAppear() {
            handler.stdOutFcn = stdout(_:)
            handler.stdInFcn = stdin
        }
    }
}

struct CommandView_Previews: PreviewProvider {
    @State static var isActive = false
    @StateObject static var handler = stdHandlers()
    @StateObject static var term = TerminalScreen()
    @State static var buf: [UInt8] = []

    static var previews: some View {
        CommandView(isActive: $isActive, handler: handler, term: term, bufferStdOut: $buf)
    }
}
