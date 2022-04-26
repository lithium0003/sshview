//
//  TerminalView.swift
//  sshview
//
//  Created by rei8 on 2022/04/21.
//

import Foundation
import SwiftUI
import GameController

protocol InvisibleTextViewDelegate {
    func insertText(text: String)
    func insertCode(code: [UInt8])
    func deleteText()
    func textInputMode()
}

class InvisibleTextView: UIView, UIKeyInput {
    var delegate: InvisibleTextViewDelegate?
    
    override var canBecomeFirstResponder: Bool { true }

    // MARK: UIKeyInput
    var keyboardType: UIKeyboardType = .asciiCapable
    
    var hasText: Bool { true }

    override func pressesBegan(_ presses: Set<UIPress>, with event: UIPressesEvent?) {
        for press in presses {
            guard let key = press.key else { continue }
            
            if key.modifierFlags.contains([.control]) {
                isCtrl = true
                ctrlButton.tintColor = .systemRed
            }

            if isCtrl {
                delegate?.insertText(text: key.characters)
                continue
            }

            switch key.keyCode {
            case .keyboardUpArrow:
                delegate?.insertCode(code: [0x1B, 0x5B, 0x41])
            case .keyboardDownArrow:
                delegate?.insertCode(code: [0x1B, 0x5B, 0x42])
            case .keyboardRightArrow:
                delegate?.insertCode(code: [0x1B, 0x5B, 0x43])
            case .keyboardLeftArrow:
                delegate?.insertCode(code: [0x1B, 0x5B, 0x44])
            default:
                super.pressesBegan(presses, with: event)
            }
        }
    }

    override func pressesEnded(_ presses: Set<UIPress>, with event: UIPressesEvent?) {
        for press in presses {
            guard let key = press.key else { continue }
            
            if key.modifierFlags.contains([.control]) {
                isCtrl = false
                ctrlButton.tintColor = nil
            }
        }
        super.pressesEnded(presses, with: event)
    }
    
    func insertText(_ text: String) {
        if isCtrl {
            isCtrl = false
            ctrlButton.tintColor = nil

            guard var value = text.data(using: .utf8)?.first else {
                return
            }
            if value >= 0x61, value <= 0x7A {
                value -= 0x20
            }
            guard value >= 0x40, value <= 0x5F else  {
                return
            }
            print("^"+text)
            let code = value & 0x1F
            delegate?.insertCode(code: [code])
        }
        else {
            print(text)
            delegate?.insertText(text: text)
        }
    }

    func deleteBackward() {
        print("(delete)")
        delegate?.deleteText()
    }
    
    private var isCtrl = false
    private lazy var ctrlButton: UIBarButtonItem = {
        UIBarButtonItem(title: "Ctrl", style: .plain, target: self, action: #selector(barButtonTapped))
    }()
    
    private lazy var toolbar: UIToolbar = {
        let toolbar = UIToolbar()
        toolbar.autoresizingMask = .flexibleHeight
        toolbar.setItems([
            UIBarButtonItem(title: "esc", style: .plain, target: self, action: #selector(barButtonTapped)),
            ctrlButton,
            UIBarButtonItem(barButtonSystemItem: .flexibleSpace, target: nil, action: nil),
            UIBarButtonItem(barButtonSystemItem: .compose, target: self, action: #selector(composeBarButtonTapped))
        ], animated: false)
        return toolbar
    }()

    @objc func composeBarButtonTapped(_ sender: UIBarButtonItem) {
        delegate?.textInputMode()
    }
    
    @objc func barButtonTapped(_ sender: UIBarButtonItem) {
        if sender.title == "esc" {
            delegate?.insertCode(code: [27])
        }
        else if sender.title == "Ctrl" {
            isCtrl.toggle()
            if isCtrl {
                sender.tintColor = .systemRed
            }
            else {
                sender.tintColor = nil
            }
        }
    }
    
    override var inputAccessoryView: UIView? {
        return self.toolbar
    }
}

struct InvisibleTextViewWrapper: UIViewRepresentable {
    typealias UIViewType = InvisibleTextView
    @Binding var isFirstResponder: Bool
    @Binding var textInputMode: Bool
    @ObservedObject var console: consoleScreen

    class Coordinator: InvisibleTextViewDelegate {
        func insertCode(code: [UInt8]) {
            parent.console.stdinHandler?(code)
        }
        
        func textInputMode() {
            parent.textInputMode.toggle()
        }
        
        func insertText(text: String) {
            parent.console.stdinHandler?(Array(text.data(using: .utf8)!))
        }
        
        func deleteText() {
            parent.console.stdinHandler?([UInt8(8)])
        }
        
        var parent: InvisibleTextViewWrapper
        
        init(_ parent: InvisibleTextViewWrapper) {
            self.parent = parent
        }
        
    }

    func makeCoordinator() -> Coordinator {
        Coordinator(self)
    }
    
    func makeUIView(context: Context) -> InvisibleTextView {
        let view = InvisibleTextView()
        view.delegate = context.coordinator
        return view
    }
    
    func updateUIView(_ uiView: InvisibleTextView, context: Context) {
        if isFirstResponder {
            DispatchQueue.main.async {
                uiView.becomeFirstResponder()
            }
        } else {
            DispatchQueue.main.async {
                uiView.resignFirstResponder()
            }
        }
    }
}

class stdHandlers: ObservableObject {
    @Published var stdOutFcn: ((ArraySlice<UInt8>)->Void)?
    @Published var stdInFcn: (()->[UInt8]?)?
    @Published var screeSizeChane: ((Int,Int)->Void)?
}

class ScreenChar {
    var text: String = " "
    var isBold = false
    var isUnderline = false
    var isBlink = false
    var isInverse = false
    var foregroundColor: UIColor = .label
    var backgroundColor: UIColor = .systemBackground
    
    init() {
    }
    
    init(other: ScreenChar, text: String = " ") {
        self.text = text
        isBold = other.isBold
        isUnderline = other.isUnderline
        isBlink = other.isBlink
        isInverse = other.isInverse
        foregroundColor = other.foregroundColor
        backgroundColor = other.backgroundColor
    }
}

class CanvasView: UIView {
    @ObservedObject var console: consoleScreen = consoleScreen()
    var timer: Timer?
    var blink = 0
    
    var sWidth: CGFloat = 0
    var sHeight: CGFloat = 0
    var scrollStart: Int = 0
    var panStart: CGPoint = .zero
    var sizeStart: CGFloat = 16

    convenience init(console: consoleScreen!) {
        self.init(frame: .zero)
        self.console = console
        self.timer = Timer.scheduledTimer(timeInterval: 1.0, target: self, selector: #selector(onTimer), userInfo: nil, repeats: true)
        backgroundColor = .clear
        
        let panGestureRecognizer = UIPanGestureRecognizer(target: self, action: #selector(didPan))
        panGestureRecognizer.allowedScrollTypesMask = [.continuous, .discrete]
        addGestureRecognizer(panGestureRecognizer)
        addGestureRecognizer(UIPinchGestureRecognizer(target: self, action: #selector(didPinch)))
    }
    
    override init(frame: CGRect) {
        super.init(frame: frame)
    }

    required init?(coder aDecoder: NSCoder) {
      super.init(coder: aDecoder)
    }
    
    
    @objc func onTimer() {
        setNeedsDisplay()
        blink += 1
        if blink > 1 {
            blink = 0
        }
    }
    
    @objc func didPan(_ gesture: UIPanGestureRecognizer) {
        let isKeyboardConnected = GCKeyboard.coalesced != nil
        if !isKeyboardConnected, gesture.numberOfTouches < 2, console.showingKeyboad {
            if gesture.state == .ended {
                let d = gesture.translation(in: self)
                let length = sqrt(d.x * d.x + d.y * d.y)
                if length < 5 {
                    return
                }
                let th = atan2(d.y, d.x)
                let count = Int(length / 50.0) + 1
                print(count, length, th)
                if th >= -CGFloat.pi / 4, th < CGFloat.pi / 4 {
                    // right
                    if console.applicationCursor {
                        for _ in 0..<count {
                            console.stdinHandler?([0x1B, 0x4F, 0x43])
                        }
                    }
                    else {
                        for _ in 0..<count {
                            console.stdinHandler?([0x1B, 0x5B, 0x43])
                        }
                    }
                }
                else if th >= CGFloat.pi / 4, th < CGFloat.pi * 3 / 4 {
                    // down
                    if console.applicationCursor {
                        for _ in 0..<count {
                            console.stdinHandler?([0x1B, 0x4F, 0x42])
                        }
                    }
                    else {
                        for _ in 0..<count {
                            console.stdinHandler?([0x1B, 0x5B, 0x42])
                        }
                    }
                }
                else if th >= -3 * CGFloat.pi / 4, th < -CGFloat.pi / 4 {
                    // up
                    if console.applicationCursor {
                        for _ in 0..<count {
                            console.stdinHandler?([0x1B, 0x4F, 0x41])
                        }
                    }
                    else {
                        for _ in 0..<count {
                            console.stdinHandler?([0x1B, 0x5B, 0x41])
                        }
                    }
                }
                else {
                    // left
                    if console.applicationCursor {
                        for _ in 0..<count {
                            console.stdinHandler?([0x1B, 0x4F, 0x44])
                        }
                    }
                    else {
                        for _ in 0..<count {
                            console.stdinHandler?([0x1B, 0x5B, 0x44])
                        }
                    }
                }
            }
            return
        }
        
        switch gesture.state {
        case .began:
            panStart = gesture.location(in: self)
            scrollStart = console.screenScroolStart
        case .changed:
            let dy = gesture.location(in: self).y - panStart.y
            console.screenScroolStart = scrollStart - Int(dy / sHeight)
            setNeedsDisplay()
        case .ended, .failed, .cancelled:
            let dy = gesture.location(in: self).y - panStart.y
            let vy = gesture.velocity(in: self).y
            console.screenScroolStart = scrollStart - Int(dy / sHeight) - Int(vy / sHeight)
            setNeedsDisplay()
        case .possible:
            break
        @unknown default:
            break
        }
    }

    @objc func didPinch(_ gesture: UIPinchGestureRecognizer) {
        switch gesture.state {
        case .began:
            sizeStart = console.fontSize
        case .changed:
            console.fontSize = max(9, sizeStart * gesture.scale)
            setNeedsDisplay()
        case .ended, .failed, .cancelled:
            console.fontSize = max(9, sizeStart * gesture.scale)
            console.fontSizeChgDone = Date()
            setNeedsDisplay()
        case .possible:
            break
        @unknown default:
            break
        }
    }

    override func draw(_ rect: CGRect){
        super.draw(rect)
        
        if console.beep {
            console.beep = false
            
            let flushView = UIView(frame: frame)
            flushView.backgroundColor = .systemBackground
            flushView.alpha = 0.5
            addSubview(flushView)
            UIView.animate(withDuration: 0.05, animations: {
                flushView.backgroundColor = .label
            }, completion: { (finished) in
                flushView.removeFromSuperview()
            })
        }
        
        let normalFont = UIFont.monospacedSystemFont(ofSize: console.fontSize, weight: .regular)
        let boldFont = UIFont.monospacedSystemFont(ofSize: console.fontSize, weight: .bold)
        let stringAttributes: [NSAttributedString.Key : Any] = [
            .font : normalFont
        ]
        let s = NSAttributedString(string: " ", attributes: stringAttributes).boundingRect(with: UIScreen.main.bounds.size, context: nil)
        sWidth = floor(s.width)
        sHeight = floor(s.height)
        
        for y in 0..<console.screenHeight {
            let ys = y + console.screenScroolStart
            guard ys < console.screenText.count else {
                continue
            }
            var xStart: CGFloat = 0
            for x in 0..<console.screenWidth {
                guard x < console.screenText[ys].count else {
                    continue
                }
                if CGFloat(x) * sWidth < xStart {
                    continue
                }
                let isCurPos = console.curX == x && console.curY == y && console.screenScroolStart == console.screenStartLine && console.showCursor
                guard let c = console.screenText[ys][x] else {
                    " ".draw(at: CGPoint(x: CGFloat(x) * sWidth, y: sHeight * CGFloat(y)), withAttributes: stringAttributes)
                    if isCurPos, blink == 0 {
                        UIColor.label.setFill()
                        UIBezierPath(rect: CGRect(origin: CGPoint(x: CGFloat(x) * sWidth, y: sHeight * CGFloat(y+1) - console.fontSize / 8), size: CGSize(width: sWidth, height: console.fontSize / 8))).fill()
                    }

                    xStart += sWidth
                    continue
                }
                var attr: [NSAttributedString.Key : Any] = [
                    .font : c.isBold ? boldFont : normalFont,
                ]
                if c.isInverse {
                    attr[.foregroundColor] = c.backgroundColor
                    attr[.backgroundColor] = c.foregroundColor
                    if blink > 0, c.isBlink {
                        attr[.foregroundColor] = c.foregroundColor
                    }
                }
                else {
                    attr[.foregroundColor] = c.foregroundColor
                    attr[.backgroundColor] = c.backgroundColor
                    if blink > 0, c.isBlink {
                        attr[.foregroundColor] = c.backgroundColor
                    }
                }
                if c.isUnderline {
                    attr[.underlineStyle] = NSUnderlineStyle.single

                }
                c.text.draw(at: CGPoint(x: CGFloat(x) * sWidth, y: sHeight * CGFloat(y)), withAttributes: attr)
                let s = NSAttributedString(string: c.text, attributes: attr).boundingRect(with: UIScreen.main.bounds.size, context: nil)
                if isCurPos, blink == 0 {
                    UIColor.label.setFill()
                    UIBezierPath(rect: CGRect(origin: CGPoint(x: CGFloat(x) * sWidth, y: sHeight * CGFloat(y+1) - console.fontSize / 8), size: CGSize(width: s.width, height: console.fontSize / 8))).fill()
                }
                xStart += floor(s.width)
            }
        }
    }
}

struct CanvasViewWrapper : UIViewRepresentable {
    @ObservedObject var console: consoleScreen

    func makeUIView(context: Context) -> UIView {
        let view = CanvasView(console: console)
        console.onUpdate = {
            view.setNeedsDisplay()
        }
        return view
    }
    
    func updateUIView(_ uiView: UIView, context: Context) {
        uiView.setNeedsDisplay()
    }
}

class consoleScreen: ObservableObject {
    @Published var screenWidth: Int = 80
    @Published var screenHeight: Int = 24
    @Published var fontSize: CGFloat = 16
    @Published var fontSizeChgDone: Date = Date()
    @Published var lastUpdate = Date()
    @Published var showingKeyboad = false
    @Published var stdinHandler: (([UInt8])->Void)?

    @Published var applicationCursor = false
    @Published var showCursor = true
    @Published var backendPasteMode = false
    
    var screenStartLine: Int = 0
    var screenScroolStart: Int = 0 {
        didSet {
            if screenScroolStart + screenHeight >= screenText.count {
                screenScroolStart = screenText.count - screenHeight
            }
            if screenScroolStart < 0 {
                screenScroolStart = 0
            }
        }
    }
    var curX = 0
    var curY = 0
    var beep = false
    var lastOutchar = ""
    
    var screenText: [[ScreenChar?]] = [[ScreenChar?]](repeating: [ScreenChar?](repeating: nil, count: 80), count: 24)
    var onUpdate: (()->Void)?
    
    func clearAll() {
        screenText = [[ScreenChar?]](repeating: [ScreenChar?](repeating: nil, count: 80), count: 24)
        curX = 0
        curY = 0
        screenStartLine = 0
        screenScroolStart = 0
    }
    
    func drawView() {
        screenScroolStart = screenStartLine
        onUpdate?()
    }
    
    func makeScreenView() -> some View {
        CanvasViewWrapper(console: self)
    }
    
    func setSize(size: CGSize) -> (width: Int, height: Int) {
        let stringAttributes: [NSAttributedString.Key : Any] = [
            .font : UIFont.monospacedSystemFont(ofSize: fontSize, weight: .regular)
        ]
        let s = NSAttributedString(string: " ", attributes: stringAttributes).boundingRect(with: UIScreen.main.bounds.size, context: nil)
        let newSize = (width: Int(ceil(size.width) / floor(s.width)), height: Int(ceil(size.height) / floor(s.height)))
        print(newSize)

        for i in 0..<screenText.count {
            if screenText[i].count < newSize.width {
                screenText[i].append(contentsOf: [ScreenChar?](repeating: nil, count: newSize.width - screenText[i].count))
            }
        }
        screenWidth = newSize.width
        screenHeight = newSize.height

        if screenStartLine + screenHeight >= screenText.count {
            let addcount = screenStartLine + screenHeight - screenText.count
            for _ in 0..<addcount {
                screenText.append([ScreenChar?](repeating: nil, count: screenWidth))
            }
        }

        if curX >= screenWidth {
            curX = screenWidth - 1
        }
        if curY >= screenHeight {
            screenStartLine += (curY - screenHeight) + 1
            curY = screenHeight - 1
        }
        
        return newSize
    }
    
    func incCur() {
        curX += 1
    }
    
    func decCur() {
        curX -= 1
        if curX >= 0 {
            return
        }

        curY -= 1
        curX = screenWidth - 1
        if curY >= 0 {
            return
        }
        
        curX = 0
        curY = 0
    }

    func CurUP() {
        curY -= 1
        if curY >= 0 {
            return
        }
        curY = 0
    }

    func CurDOWN() {
        curY += 1
        if curY < screenHeight {
            return
        }
        curY = screenHeight - 1
    }

    func CurLEFT() {
        curX -= 1
        if curX >= 0 {
            return
        }
        curX = 0
    }

    func CurRIGHT() {
        curX += 1
        if curX < screenWidth {
            return
        }
        curX = screenWidth - 1
    }

    func setCurPos(x: Int, y: Int) {
        curX = x
        curY = y
        if curX < 0 {
            curX = 0
        }
        if curX >= screenWidth {
            curX = screenWidth - 1
        }
        if curY < 0 {
            curY = 0
        }
        if curY >= screenHeight {
            curY = screenHeight - 1
        }
    }
    
    func eraseDisplay(c: Int) {
        switch c {
        case 0:
            for x in curX..<screenWidth {
                screenText[screenStartLine+curY][x] = nil
            }
            for y in curY..<screenHeight {
                for x in 0..<screenWidth {
                    screenText[screenStartLine+y][x] = nil
                }
            }
        case 1:
            for x in 0...curX {
                screenText[screenStartLine+curY][x] = nil
            }
            for y in 0...curY {
                for x in 0..<screenWidth {
                    screenText[screenStartLine+y][x] = nil
                }
            }
        case 2:
            for y in 0..<screenHeight {
                for x in 0..<screenWidth {
                    screenText[screenStartLine+y][x] = nil
                }
            }
        default:
            break
        }
    }

    func eraseLine(c: Int) {
        switch c {
        case 0:
            for x in curX..<screenWidth {
                screenText[screenStartLine+curY][x] = nil
            }
        case 1:
            for x in 0...curX {
                screenText[screenStartLine+curY][x] = nil
            }
        case 2:
            for x in 0..<screenWidth {
                screenText[screenStartLine+curY][x] = nil
            }
        default:
            break
        }
    }

    func insertLine(c: Int) {
        for _ in 0..<c {
            screenText.insert([ScreenChar?](repeating: nil, count: screenWidth), at: curY + screenStartLine)
        }
    }

    func deleteLine(c: Int) {
        for _ in 0..<c {
            if curY + screenStartLine < screenText.count {
                screenText.remove(at: curY + screenStartLine)
            }
        }

        if screenStartLine + screenHeight < screenText.count {
            return
        }

        let addcount = screenStartLine + screenHeight - screenText.count
        if addcount > 0 {
            for _ in 0..<addcount {
                screenText.append([ScreenChar?](repeating: nil, count: screenWidth))
            }
        }
    }

    func deleteRight(c: Int) {
        for _ in 0..<c {
            if c + curX < screenWidth, c + curX < screenText[screenStartLine+curY].count {
                screenText[screenStartLine+curY].remove(at: curX + c)
            }
            let addcount = screenWidth - screenText[screenStartLine+curY].count
            if addcount > 0 {
                for _ in 0..<addcount {
                    screenText[screenStartLine+curY].append(nil)
                }
            }
        }
    }

    func eraseRight(c: Int) {
        for _ in 0..<c {
            if c + curX < screenWidth {
                screenText[screenStartLine+curY][curX + c] = nil
            }
        }
    }

    func scrollUp(c: Int) {
        screenStartLine -= c
        if screenStartLine < 0 {
            screenStartLine = 0
        }
        screenScroolStart = screenStartLine
    }

    func scrollDown(c: Int) {
        screenStartLine += c
        screenScroolStart = screenStartLine

        if screenStartLine + screenHeight < screenText.count {
            return
        }

        let addcount = screenStartLine + screenHeight - screenText.count
        for _ in 0..<addcount {
            screenText.append([ScreenChar?](repeating: nil, count: screenWidth))
        }
    }

    func LF() {
        curY += 1
        if curY < screenHeight {
            return
        }

        curY -= 1
        screenStartLine += 1
        if screenStartLine + screenHeight < screenText.count {
            return
        }

        let addcount = screenStartLine + screenHeight - screenText.count
        for _ in 0..<addcount {
            screenText.append([ScreenChar?](repeating: nil, count: screenWidth))
        }
    }
    
    func CR() {
        curX = 0
    }
    
    func BS() {
        decCur()
    }
    
    func DEL() {
        writeCur(nil)
    }
    
    func SPACE() {
        writeCur(nil)
        incCur()
    }
    
    func TAB(_ count: Int = 1) {
        var count = count
        let remain = curX % 8
        if remain > 0 {
            for _ in 0..<remain {
                incCur()
            }
            count -= 1
        }
        for _ in 0..<count {
            let y = curY
            for _ in 0..<8 {
                incCur()
                if y < curY {
                    break
                }
            }
        }
    }
    
    func justifyCur() {
        if curX < screenWidth {
            return
        }

        curY += 1
        curX = 0
        if curY < screenHeight {
            return
        }
        
        curY -= 1
        screenStartLine += 1
        if screenStartLine + screenHeight < screenText.count {
            return
        }

        let addcount = screenStartLine + screenHeight - screenText.count
        for _ in 0..<addcount {
            screenText.append([ScreenChar?](repeating: nil, count: screenWidth))
        }
    }
    
    func writeCur(_ value: ScreenChar?) {
        justifyCur()
        
        screenText[screenStartLine+curY][curX] = value
        lastOutchar = value?.text ?? ""
    }
}

class TerminalScreen: ObservableObject {
    @ObservedObject var screen = consoleScreen()
    
    @Published var screenBuffer: [UInt8] = []
    @Published var windowTitle: String = ""
    
    @Published var expandLF: Bool = false
    
    enum codetype: Int {
        case xx = 0xF1 // invalid: size 1
        case ac = 0xF0 // ASCII: size 1
        case s1 = 0x02 // accept 0, size 2
        case s2 = 0x13 // accept 1, size 3
        case s3 = 0x03 // accept 0, size 3
        case s4 = 0x23 // accept 2, size 3
        case s5 = 0x34 // accept 3, size 4
        case s6 = 0x04 // accept 0, size 4
        case s7 = 0x44 // accept 4, size 4
    }

    let firstByte: [codetype] = [
        //    1    2    3    4    5    6    7    8    9    A    B    C    D    E    F
        .ac, .ac, .ac, .ac, .ac, .ac, .ac, .ac, .ac, .ac, .ac, .ac, .ac, .ac, .ac, .ac, // 0x00-0x0F
        .ac, .ac, .ac, .ac, .ac, .ac, .ac, .ac, .ac, .ac, .ac, .ac, .ac, .ac, .ac, .ac, // 0x10-0x1F
        .ac, .ac, .ac, .ac, .ac, .ac, .ac, .ac, .ac, .ac, .ac, .ac, .ac, .ac, .ac, .ac, // 0x20-0x2F
        .ac, .ac, .ac, .ac, .ac, .ac, .ac, .ac, .ac, .ac, .ac, .ac, .ac, .ac, .ac, .ac, // 0x30-0x3F
        .ac, .ac, .ac, .ac, .ac, .ac, .ac, .ac, .ac, .ac, .ac, .ac, .ac, .ac, .ac, .ac, // 0x40-0x4F
        .ac, .ac, .ac, .ac, .ac, .ac, .ac, .ac, .ac, .ac, .ac, .ac, .ac, .ac, .ac, .ac, // 0x50-0x5F
        .ac, .ac, .ac, .ac, .ac, .ac, .ac, .ac, .ac, .ac, .ac, .ac, .ac, .ac, .ac, .ac, // 0x60-0x6F
        .ac, .ac, .ac, .ac, .ac, .ac, .ac, .ac, .ac, .ac, .ac, .ac, .ac, .ac, .ac, .ac, // 0x70-0x7F
        //    1    2    3    4    5    6    7    8    9    A    B    C    D    E    F
        .xx, .xx, .xx, .xx, .xx, .xx, .xx, .xx, .xx, .xx, .xx, .xx, .xx, .xx, .xx, .xx, // 0x80-0x8F
        .xx, .xx, .xx, .xx, .xx, .xx, .xx, .xx, .xx, .xx, .xx, .xx, .xx, .xx, .xx, .xx, // 0x90-0x9F
        .xx, .xx, .xx, .xx, .xx, .xx, .xx, .xx, .xx, .xx, .xx, .xx, .xx, .xx, .xx, .xx, // 0xA0-0xAF
        .xx, .xx, .xx, .xx, .xx, .xx, .xx, .xx, .xx, .xx, .xx, .xx, .xx, .xx, .xx, .xx, // 0xB0-0xBF
        .xx, .xx, .s1, .s1, .s1, .s1, .s1, .s1, .s1, .s1, .s1, .s1, .s1, .s1, .s1, .s1, // 0xC0-0xCF
        .s1, .s1, .s1, .s1, .s1, .s1, .s1, .s1, .s1, .s1, .s1, .s1, .s1, .s1, .s1, .s1, // 0xD0-0xDF
        .s2, .s3, .s3, .s3, .s3, .s3, .s3, .s3, .s3, .s3, .s3, .s3, .s3, .s4, .s3, .s3, // 0xE0-0xEF
        .s5, .s6, .s6, .s6, .s7, .xx, .xx, .xx, .xx, .xx, .xx, .xx, .xx, .xx, .xx, .xx, // 0xF0-0xFF
    ]
    
    let acceptRanges: [Int: (lo: UInt8, hi: UInt8)] = [
        0: (0x80, 0xBF),
        1: (0xA0, 0xBF),
        2: (0x80, 0x9F),
        3: (0x90, 0xBF),
        4: (0x80, 0x8F),
    ]
    
    func renderScreen() {
        var c_size = 0
        var c_accept = acceptRanges[0]!
        var c_i = 0
        var escSequence: [UInt8] = []
        var tmpBuf: [UInt8] = []
        
        var curChar = ScreenChar()
        print(screenBuffer)
        for c in screenBuffer {
            if escSequence.count > 0  {
                if c == 0x1B {
                    // ESC
                    escSequence.append(c)
                    continue
                }
                if escSequence.count == 1 {
                    switch c {
                    case 0x21,0x22,0x24,0x28...0x2B,0x2D...0x2F:
                        escSequence.append(c)
                        continue
                    default:
                        break
                    }
                }
                else if escSequence.count == 2 {
                    switch escSequence[1] {
                    case 0x21,0x22,0x28...0x2B,0x2D...0x2F:
                        if c < 0x40 || c > 0x7F {
                            // invalid
                            escSequence = []
                            continue
                        }
                        
                        print(escSequence)
                        escSequence = []
                        continue
                    case 0x24:
                        switch c {
                        case 0x28...0x2B,0x2D...0x2F:
                            escSequence.append(c)
                            continue
                        default:
                            // invalid
                            escSequence = []
                            continue
                        }
                    default:
                        break
                    }
                }
                else if escSequence.count == 3, escSequence[1] == 0x24 {
                    if (escSequence[2] >= 0x28 && escSequence[2] <= 0x2B) || (escSequence[2] >= 0x2D && escSequence[2] <= 0x2F) {

                        if c < 0x40 || c > 0x7F {
                            // invalid
                            escSequence = []
                            continue
                        }
                        escSequence.append(c)

                        print(escSequence)
                        escSequence = []
                        continue
                    }
                }

                if escSequence.count > 2, escSequence[1] == 0x5D {
                    // OSC
                    if (c != 7 && c < 0x20) || c > 0x7F {
                        // invalid
                        escSequence = []
                        continue
                    }
                }
                else {
                    if c < 0x20 || c > 0x7F {
                        // invalid
                        escSequence = []
                        continue
                    }
                }
                escSequence.append(c)
                
                
                if escSequence[1] == 0x44 {
                    // IND
                    // ESC D
                    
                    // Moves the cursor down one line in the same column.
                    escSequence = []
                    screen.CurDOWN()
                    continue
                }
                if escSequence[1] == 0x45 {
                    // RI
                    // ESC M
                    
                    escSequence = []
                    
                    // Moves the cursor to the first position on the next line.
                    let y = screen.curY
                    screen.setCurPos(x: 0, y: y+1)
                    continue
                }
                if escSequence[1] == 0x48 {
                    // HTS
                    // ESC H
                    
                    escSequence = []
                    // no implements
                    continue
                }
                if escSequence[1] == 0x4D {
                    // RI
                    // ESC M
                    
                    escSequence = []
                    
                    // Moves the cursor up one line in the same column.
                    screen.CurUP()
                    continue
                }

                if escSequence[1] == 0x3D {
                    // DECKPAM
                    // ESC =
                    
                    escSequence = []
                    // no implements
                    continue
                }
                if escSequence[1] == 0x3E {
                    // DECKPNM
                    // ESC >
                    
                    escSequence = []
                    // no implements
                    continue
                }
                if escSequence[1] == 0x58 {
                    // SOS
                    // ESC X
                    let st = escSequence.suffix(2)
                    if st.count < 2 {
                        continue
                    }
                    if st[st.startIndex] != 0x1B || st[st.startIndex+1] != 0x5C {
                        // SOS Pt ST
                        escSequence = []
                        // no implements
                        continue
                    }
                    continue
                }
                if escSequence[1] == 0x5E {
                    // PM
                    // ESC ^
                    let st = escSequence.suffix(2)
                    if st.count < 2 {
                        continue
                    }
                    if st[st.startIndex] != 0x1B || st[st.startIndex+1] != 0x5C {
                        // SOS Pt ST
                        escSequence = []
                        // no implements
                        continue
                    }
                    continue
                }
                if escSequence[1] == 0x5F {
                    // APC
                    // ESC _
                    let st = escSequence.suffix(2)
                    if st.count < 2 {
                        continue
                    }
                    if st[st.startIndex] != 0x1B || st[st.startIndex+1] != 0x5C {
                        // SOS Pt ST
                        escSequence = []
                        // no implements
                        continue
                    }
                    continue
                }
                if escSequence[1] == 0x5C {
                    // ST
                    // ESC \
                    escSequence = []
                    continue
                }
                if escSequence[1] == 0x5B {
                    // CSI
                    // ESC [
                    
                    if escSequence.count < 3 {
                        continue
                    }

                    let endc = escSequence.last!
                    if endc < 0x40 || endc > 0x7E {
                        continue
                    }
                    
                    let command = String(bytes: [endc], encoding: .utf8)!
                    let Pt = String(bytes: escSequence[2...].dropLast(), encoding: .utf8)!
                    
                    print(Pt, command)
                    if command == "@" {
                        // ICH
                        // CSI Ps @

                        // Insert Ps space (SP) characters starting at the cursor position.
                        // The default value of Ps is 1.
                        let count = Int(Pt) ?? 1
                        for _ in 0..<count {
                            screen.SPACE()
                        }
                    }
                    else if command == "A" {
                        // CUU
                        // CSI Ps A

                        // Moves cursor up Ps lines in the same column.
                        // The default value of Ps is 1.
                        let count = Int(Pt) ?? 1
                        for _ in 0..<count {
                            screen.CurUP()
                        }
                    }
                    else if command == "B" {
                        // CUD
                        // CSI Ps B

                        // Moves cursor down Ps lines in the same column.
                        // The default value of Ps is 1.
                        let count = Int(Pt) ?? 1
                        for _ in 0..<count {
                            screen.CurDOWN()
                        }
                    }
                    else if command == "C" {
                        // CUF
                        // CSI Ps C

                        // Moves cursor to the right Ps columns.
                        // The default value of Ps is 1.
                        let count = Int(Pt) ?? 1
                        for _ in 0..<count {
                            screen.CurRIGHT()
                        }
                    }
                    else if command == "D" {
                        // CUB
                        // CSI Ps D

                        // Moves cursor to the left Ps columns.
                        // The default value of Ps is 1.
                        let count = Int(Pt) ?? 1
                        for _ in 0..<count {
                            screen.CurLEFT()
                        }
                    }
                    else if command == "E" {
                        // CNL
                        // CSI Ps E

                        // Moves cursor to the first column of Ps-th following line.
                        // The default value of Ps is 1.
                        let count = Int(Pt) ?? 1
                        screen.setCurPos(x: 0, y: screen.curY + count)
                    }
                    else if command == "F" {
                        // CPL
                        // CSI Ps F

                        // Moves cursor to the first column of Ps-th preceding line.
                        // The default value of Ps is 1.
                        let count = Int(Pt) ?? 1
                        screen.setCurPos(x: 0, y: screen.curY - count)
                    }
                    else if command == "G" {
                        // CHA
                        // CSI Ps G

                        // Moves cursor to the Ps-th column of the active line.
                        // The default value of Ps is 1.
                        let count = Int(Pt) ?? 1
                        screen.setCurPos(x: count - 1, y: screen.curY)
                    }
                    else if command == "H" {
                        // CUP
                        
                        // CSI Ps1 ; Ps2 H
                        // Moves cursor to the Ps1-th line and to the Ps2-th column.
                        // The default value of Ps1 and Ps2 is 1.
                        let Ps = Pt.split(separator: ";")
                        var Ps1 = 1
                        var Ps2 = 1
                        if Ps.count == 1 {
                            Ps1 = Int(Ps[0]) ?? 1
                        }
                        else if Ps.count >= 2 {
                            Ps1 = Int(Ps[0]) ?? 1
                            Ps2 = Int(Ps[1]) ?? 1
                        }
                        
                        screen.setCurPos(x: Ps2 - 1, y: Ps1 - 1)
                    }
                    else if command == "I" {
                        // CHT
                        // CSI Ps I

                        // Moves cursor to the Ps tabs forward.
                        // The default value of Ps is 1.
                        let count = Int(Pt) ?? 1
                        screen.TAB(count)
                    }
                    else if command == "J" {
                        // ED
                        // CSI Ps J
                        // Erase in display. The default value of Ps is 0.
                        //    Ps = 0      Erase from cursor through the end of the display.
                        //       = 1      Erase from the beginning of the display through the cursor.
                        //       = 2      Erase the complete of display.

                        let code = Int(Pt) ?? 0
                        screen.eraseDisplay(c: code)
                    }
                    else if command == "K" {
                        // EL
                        // CSI Ps K
                        // Erase in line. The default value of Ps is 0.
                        // Ps = 0      Erase from the cursor through the end of the line.
                        //    = 1      Erase from the beginning of the line through the cursor.
                        //    = 2      Erase the complete of line.

                        let code = Int(Pt) ?? 0
                        screen.eraseLine(c: code)
                    }
                    else if command == "L" {
                        // IL
                        // CSI Ps L

                        // Inserts Ps lines, starting at the cursor.
                        // The default value of Ps is 1.
                        let code = Int(Pt) ?? 1
                        screen.insertLine(c: code)
                    }
                    else if command == "M" {
                        // DL
                        // CSI Ps M

                        // Deletes Ps lines in the scrolling region,
                        // starting with the line that has the cursor.
                        // The default value of Ps is 1.
                        let code = Int(Pt) ?? 1
                        screen.deleteLine(c: code)
                    }
                    else if command == "P" {
                        // DCH
                        // CSI Ps P

                        // Deletes Ps characters from the cursor position to the right.
                        // The default value of Ps is 1.
                        let code = Int(Pt) ?? 1
                        screen.deleteRight(c: code)
                    }
                    else if command == "S" {
                        // SU
                        // CSI Ps S

                        // Scroll up Ps lines. The default value of Ps is 1.
                        let code = Int(Pt) ?? 1
                        screen.scrollUp(c: code)
                    }
                    else if command == "T" {
                        // SD
                        // CSI Ps T

                        // Scroll up Ps lines. The default value of Ps is 1.
                        let code = Int(Pt) ?? 1
                        screen.scrollDown(c: code)
                    }
                    else if command == "X" {
                        // ECH
                        // CSI Ps X

                        // Erase Ps characters, from the cursor position to the right.
                        // The default value of Ps is 1.
                        let code = Int(Pt) ?? 1
                        screen.eraseRight(c: code)
                    }
                    else if command == "Z" {
                        // CBT
                        // CSI Ps Z

                        // Moves cursor to the Ps tabs backward.
                        // The default value of Ps is 1.
                        let code = Int(Pt) ?? 1
                        let y = screen.curY
                        let tx = screen.curX / 8 - code + 1
                        if tx < 0 {
                            screen.setCurPos(x: 0, y: y)
                        }
                        else {
                            screen.setCurPos(x: tx * 8, y: y)
                        }
                    }
                    else if command == "`" {
                        // HPA
                        // CSI Ps `

                        // Moves cursor to the Ps-th column of the active line.
                        // The default value of Ps is 1.
                        let code = Int(Pt) ?? 1
                        let y = screen.curY
                        screen.setCurPos(x: code - 1, y: y)
                    }
                    else if command == "a" {
                        // HPR
                        // CSI Ps a

                        // Moves cursor to the right Ps columns.
                        // The default value of Ps is 1.
                        let code = Int(Pt) ?? 1
                        let x = screen.curX
                        let y = screen.curY
                        screen.setCurPos(x: x + code, y: y)
                    }
                    else if command == "b" {
                        // REP
                        // CSI Ps b

                        // Repeat the last output character Ps times.
                        // The default value of Ps is 1.
                        let code = Int(Pt) ?? 1
                        for _ in 0..<code {
                            curChar = ScreenChar(other: curChar)
                            screen.writeCur(ScreenChar(other: curChar, text: screen.lastOutchar))
                            screen.incCur()
                        }
                    }
                    else if command == "d" {
                        // VPA
                        // CSI Ps d

                        // Move to the corresponding vertical position (line Ps) of the current column.
                        // The default value of Ps is 1.
                        let code = Int(Pt) ?? 1
                        let x = screen.curX
                        screen.setCurPos(x: x, y: code - 1)
                    }
                    else if command == "e" {
                        // VPR
                        // CSI Ps e

                        // Moves cursor down Ps lines in the same column.
                        // The default value of Ps is 1.
                        let code = Int(Pt) ?? 1
                        let x = screen.curX
                        let y = screen.curY
                        screen.setCurPos(x: x, y: y + code)
                    }
                    else if command == "f" {
                        // HVP
                        // CSI Ps1 ; Ps2 f

                        // Moves cursor to the Ps1-th line and to the Ps2-th column.
                        // The default value of Ps1 and Ps2 is 1.
                        let code = Pt.split(separator: ";")
                        let Ps1 = code.count > 0 ? (Int(code[0]) ?? 1) : 1
                        let Ps2 = code.count > 1 ? (Int(code[1]) ?? 1) : 1
                        screen.setCurPos(x: Ps1 - 1, y: Ps2 - 1)
                    }
                    else if Pt.prefix(1) == "?", command == "h" {
                        // DECSET
                        let code = Int(Pt.dropFirst()) ?? -1
                        switch code {
                        case 1:
                            // DECCKM
                            // Application cursor keys.
                            
                            screen.applicationCursor = true
                        case 25:
                            // DECTCEM
                            // Show cursor.
                            
                            screen.showCursor = true
                        case 2004:
                            // RL_BRACKET
                            // Enables Bracketed paste mode
                            
                            screen.backendPasteMode = true
                        default:
                            break
                        }
                    }
                    else if command == "j" {
                        // HPB
                        // CSI Ps j

                        // Moves cursor to the left Ps columns.
                        // The default value of Ps is 1.
                        let code = Int(Pt) ?? 1
                        let x = screen.curX
                        let y = screen.curY
                        screen.setCurPos(x: x - code, y: y)
                    }
                    else if command == "k" {
                        // VPB
                        // CSI Ps k

                        // Moves cursor up Ps lines in the same column.
                        // The default value of Ps is 1.
                        let code = Int(Pt) ?? 1
                        let x = screen.curX
                        let y = screen.curY
                        screen.setCurPos(x: x, y: y - code)
                    }
                    else if Pt.prefix(1) == "?", command == "l" {
                        // DECRST
                        let code = Int(Pt.dropFirst()) ?? -1
                        switch code {
                        case 1:
                            // DECCKM
                            // Normal cursor keys.
                            
                            screen.applicationCursor = false
                        case 25:
                            // DECTCEM
                            // Hide cursor.
                            
                            screen.showCursor = false
                        case 2004:
                            // RL_BRACKET
                            // Disables Bracketed paste mode
                            
                            screen.backendPasteMode = false
                        default:
                            break
                        }
                    }
                    else if command == "m" {
                        // SGR
                        var code = Pt.split(separator: ";")
                        if code.isEmpty {
                            code = ["0"]
                        }
                        var lastcode: [Int] = []
                        for c in code {
                            if lastcode.count == 1 {
                                lastcode.append(Int(c) ?? -1)
                                continue
                            }
                            if lastcode.count == 2, lastcode[1] == 5 {
                                let color: UIColor
                                let i = Int(c) ?? 0
                                switch i {
                                case 0:
                                    color = .black
                                case 1:
                                    color = UIColor(red: 0.75, green: 0.0, blue: 0.0, alpha: 1.0)
                                case 2:
                                    color = UIColor(red: 0.0, green: 0.75, blue: 0.0, alpha: 1.0)
                                case 3:
                                    color = UIColor(red: 0.75, green: 0.75, blue: 0.0, alpha: 1.0)
                                case 4:
                                    color = UIColor(red: 0.0, green: 0.0, blue: 0.75, alpha: 1.0)
                                case 5:
                                    color = UIColor(red: 0.75, green: 0.0, blue: 0.75, alpha: 1.0)
                                case 6:
                                    color = UIColor(red: 0.0, green: 0.75, blue: 0.75, alpha: 1.0)
                                case 7:
                                    color = UIColor(red: 0.75, green: 0.75, blue: 0.75, alpha: 1.0)
                                case 8:
                                    color = UIColor(red: 0.25, green: 0.25, blue: 0.25, alpha: 1.0)
                                case 9:
                                    color = .red
                                case 10:
                                    color = .green
                                case 11:
                                    color = .yellow
                                case 12:
                                    color = .blue
                                case 13:
                                    color = .magenta
                                case 14:
                                    color = .cyan
                                case 15:
                                    color = .white
                                case 16...231:
                                    let r = (i - 16) / 36
                                    let g = ((i - 16) / 6) % 6
                                    let b = (i - 16) % 6
                                    let v = [0, 95, 135, 175, 215, 255]
                                    color = UIColor(red: CGFloat(v[r]) / 255.0, green: CGFloat(v[g]) / 255.0, blue: CGFloat(v[b]) / 255.0, alpha: 1.0)
                                case 232...255:
                                    let v = [8, 18, 28, 38, 48, 58, 68, 78, 88, 98, 108, 118, 128, 138, 148, 158, 168, 178, 188, 198, 208, 218, 228, 238]
                                    color = UIColor(white: CGFloat(v[i - 232]), alpha: 1.0)
                                default:
                                    color = .label
                                }
                                
                                if lastcode[0] == 38 {
                                    curChar.foregroundColor = color
                                }
                                else if lastcode[0] == 48 {
                                    curChar.backgroundColor = color
                                }
                                lastcode = []
                                continue
                            }
                            if lastcode.count >= 2, lastcode[1] == 2 {
                                if lastcode.count < 5 {
                                    lastcode.append(Int(c) ?? -1)
                                    continue
                                }
                                
                                let r = lastcode[2]
                                let g = lastcode[3]
                                let b = lastcode[4]
                                
                                let color = UIColor(red: CGFloat(r) / 255.0, green: CGFloat(g) / 255.0, blue: CGFloat(b) / 255.0, alpha: 1.0)
                                
                                if lastcode[0] == 38 {
                                    curChar.foregroundColor = color
                                }
                                else if lastcode[0] == 48 {
                                    curChar.backgroundColor = color
                                }
                                lastcode = []
                                continue
                            }
                            
                            switch Int(c) {
                            case 0:
                                // Normal
                                curChar = ScreenChar()
                            case 1:
                                // Bold
                                curChar.isBold = true
                            case 4:
                                // Underlined
                                curChar.isUnderline = true
                            case 5:
                                // Blink
                                curChar.isBlink = true
                            case 7:
                                // Inverse
                                curChar.isInverse = true
                            case 22:
                                // Normal (neither bold nor faint)
                                curChar.isBold = false
                            case 24:
                                // Not underlined
                                curChar.isUnderline = false
                            case 25:
                                // Steady (not blinking)
                                curChar.isBlink = false
                            case 27:
                                // Positive (not inverse)
                                curChar.isInverse = false
                            case 30:
                                // Set foreground color to Black. (Color No. 0)
                                curChar.foregroundColor = .black
                            case 31:
                                // Set foreground color to Red. (Color No. 1)
                                curChar.foregroundColor = .red
                            case 32:
                                // Set foreground color to Green. (Color No. 2)
                                curChar.foregroundColor = .green
                            case 33:
                                // Set foreground color to Yellow. (Color No. 3)
                                curChar.foregroundColor = .yellow
                            case 34:
                                // Set foreground color to Blue. (Color No. 4)
                                curChar.foregroundColor = .blue
                            case 35:
                                // Set foreground color to Magenta. (Color No. 5)
                                curChar.foregroundColor = .magenta
                            case 36:
                                // Set foreground color to Cyan. (Color No. 6)
                                curChar.foregroundColor = .cyan
                            case 37:
                                // Set foreground color to White. (Color No. 7)
                                curChar.foregroundColor = .white
                            case 38:
                                lastcode = [38]
                            case 39:
                                // Set foreground color to default.
                                curChar.foregroundColor = .label
                            case 40:
                                // Set background color to Black. (Color No. 0)
                                curChar.backgroundColor = .black
                            case 41:
                                // Set background color to Red. (Color No. 1)
                                curChar.backgroundColor = .red
                            case 42:
                                // Set background color to Green. (Color No. 2)
                                curChar.backgroundColor = .green
                            case 43:
                                // Set background color to Yellow. (Color No. 3)
                                curChar.backgroundColor = .yellow
                            case 44:
                                // Set background color to Blue. (Color No. 4)
                                curChar.backgroundColor = .blue
                            case 45:
                                // Set background color to Magenta. (Color No. 5)
                                curChar.backgroundColor = .magenta
                            case 46:
                                // Set background color to Cyan. (Color No. 6)
                                curChar.backgroundColor = .cyan
                            case 47:
                                // Set background color to White. (Color No. 7)
                                curChar.backgroundColor = .white
                            case 48:
                                lastcode = [48]
                            case 49:
                                // Set background color to default.
                                curChar.backgroundColor = .systemBackground
                            default:
                                break
                            }
                        }
                    }
                    
                    escSequence = []
                    continue
                }
                if escSequence[1] == 0x5D {
                    // OSC
                    // ESC ]
                    
                    if escSequence.last! != 7 {
                        let st = escSequence.suffix(2)
                        if st.count < 2 {
                            continue
                        }
                        if st[st.startIndex] != 0x1B || st[st.startIndex+1] != 0x5C {
                            continue
                        }
                        escSequence = escSequence.dropLast(2)
                    }
                    else {
                        escSequence = escSequence.dropLast()
                    }
                    // OSC Ps ; Pt ST
                    // OSC Ps ; Pt BEL
                    
                    escSequence = Array(escSequence[2...])
                    let v = escSequence.split(separator: 0x3B, maxSplits: 1, omittingEmptySubsequences: false)
                    if v.count == 2 {
                        let Ps = String(bytes: v[0], encoding: .utf8)!
                        let Pt = String(bytes: v[1], encoding: .utf8)!
                        print(Ps, Pt)
                        if Ps == "0" || Ps == "1" || Ps == "2" {
                            // window title
                            windowTitle = Pt
                        }
                        else if Ps == "4" {
                            // Change color
                        }
                    }
                    
                    escSequence = []
                    continue
                }
            }
            if c_i == 0{
                if c < 0x80 {
                    // single ascii
                    if c == 7 {
                        // BEL
                        screen.beep = true
                        continue
                    }
                    if c == 8 {
                        // BS
                        screen.BS()
                        continue
                    }
                    if c == 9 {
                        screen.TAB()
                        continue
                    }
                    if c == 0x0A || c == 0x0C {
                        // LF, FF
                        screen.LF()
                        if expandLF {
                            screen.CR()
                        }
                        continue
                    }
                    if c == 0x0D {
                        // CR
                        screen.CR()
                        continue
                    }
                    if c == 0x1B {
                        // ESC
                        escSequence = [c]
                        continue
                    }
                    if c == 0x7F {
                        // DEL
                        screen.DEL()
                        continue
                    }
                    curChar = ScreenChar(other: curChar)
                    screen.writeCur(ScreenChar(other: curChar, text: String(bytes: [c], encoding: .utf8)!))
                    screen.incCur()
                    continue
                }
                let x = firstByte[Int(c)]
                if x == .xx {
                    // invalid
                    tmpBuf = []
                    c_i = 0
                    continue
                }
                c_size = x.rawValue & 7
                c_accept = acceptRanges[x.rawValue >> 4]!
                c_i = 1
                tmpBuf += [c]
            }
            else {
                if c < c_accept.lo || c > c_accept.hi {
                    // invalid
                    tmpBuf = []
                    c_i = 0
                    continue
                }
                c_i += 1
                tmpBuf += [c]
                if c_size == c_i {
                    c_i = 0
                    curChar = ScreenChar(other: curChar)
                    screen.writeCur(ScreenChar(other: curChar, text: String(bytes: tmpBuf, encoding: .utf8)!))
                    screen.incCur()
                    screen.writeCur(nil)
                    screen.incCur()
                    tmpBuf = []
                    continue
                }
                c_accept = acceptRanges[0]!
            }
        }
        screenBuffer = []
        screen.drawView()
    }
}

