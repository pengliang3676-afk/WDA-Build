import UIKit
import Network

final class KeyboardViewController: UIInputViewController {
    private let queue = DispatchQueue(label: "com.jibeib.starkeyboard.listener")
    private var listener: NWListener?
    private var connections: [NWConnection] = []
    private let statusLabel = UILabel()

    override func viewDidLoad() {
        super.viewDidLoad()
        buildInterface()
        startListener()
    }

    override func viewWillDisappear(_ animated: Bool) {
        super.viewWillDisappear(animated)
        stopListener()
    }

    private func buildInterface() {
        view.backgroundColor = UIColor(red: 0.04, green: 0.08, blue: 0.15, alpha: 1)

        statusLabel.text = "星蓝输入法 · 等待 USB 输入"
        statusLabel.textColor = .white
        statusLabel.font = .boldSystemFont(ofSize: 17)
        statusLabel.textAlignment = .center

        let hint = UILabel()
        hint.text = "请在电脑端直接输入中文、英文或数字"
        hint.textColor = UIColor(white: 0.78, alpha: 1)
        hint.font = .systemFont(ofSize: 14)
        hint.textAlignment = .center

        let nextKeyboard = UIButton(type: .system)
        nextKeyboard.setTitle("切换键盘", for: .normal)
        nextKeyboard.setTitleColor(.white, for: .normal)
        nextKeyboard.backgroundColor = UIColor(red: 0.18, green: 0.23, blue: 0.32, alpha: 1)
        nextKeyboard.layer.cornerRadius = 8
        nextKeyboard.addTarget(self, action: #selector(handleInputModeList(from:with:)), for: .allTouchEvents)

        let stack = UIStackView(arrangedSubviews: [statusLabel, hint, nextKeyboard])
        stack.axis = .vertical
        stack.spacing = 12
        stack.translatesAutoresizingMaskIntoConstraints = false
        view.addSubview(stack)

        NSLayoutConstraint.activate([
            view.heightAnchor.constraint(equalToConstant: 180),
            stack.leadingAnchor.constraint(equalTo: view.leadingAnchor, constant: 16),
            stack.trailingAnchor.constraint(equalTo: view.trailingAnchor, constant: -16),
            stack.topAnchor.constraint(equalTo: view.topAnchor, constant: 18),
            nextKeyboard.heightAnchor.constraint(equalToConstant: 44)
        ])
    }

    private func startListener() {
        stopListener()
        do {
            let parameters = NWParameters.tcp
            parameters.allowLocalEndpointReuse = true
            let listener = try NWListener(using: parameters, on: 6001)
            listener.newConnectionHandler = { [weak self] connection in
                self?.accept(connection)
            }
            listener.stateUpdateHandler = { [weak self] state in
                DispatchQueue.main.async {
                    switch state {
                    case .ready:
                        self?.statusLabel.text = "星蓝输入法 · USB 已就绪"
                    case .failed(let error):
                        self?.statusLabel.text = "端口启动失败：\(error.localizedDescription)"
                    default:
                        break
                    }
                }
            }
            listener.start(queue: queue)
            self.listener = listener
        } catch {
            statusLabel.text = "端口启动失败"
        }
    }

    private func stopListener() {
        listener?.cancel()
        listener = nil
        connections.forEach { $0.cancel() }
        connections.removeAll()
    }

    private func accept(_ connection: NWConnection) {
        connections.append(connection)
        connection.stateUpdateHandler = { [weak self, weak connection] state in
            if case .failed = state, let connection {
                self?.connections.removeAll { $0 === connection }
            }
            if case .cancelled = state, let connection {
                self?.connections.removeAll { $0 === connection }
            }
        }
        connection.start(queue: queue)
        receive(on: connection, buffer: Data())
    }

    private func receive(on connection: NWConnection, buffer: Data) {
        connection.receive(minimumIncompleteLength: 1, maximumLength: 65536) { [weak self] data, _, complete, error in
            guard let self else { return }
            var pending = buffer
            if let data {
                pending.append(data)
                while let range = pending.range(of: Data([13, 10])) {
                    let lineData = pending.subdata(in: pending.startIndex..<range.lowerBound)
                    pending.removeSubrange(pending.startIndex..<range.upperBound)
                    if let line = String(data: lineData, encoding: .utf8) {
                        self.handle(line)
                    }
                }
            }
            if complete || error != nil {
                connection.cancel()
                self.connections.removeAll { $0 === connection }
                return
            }
            self.receive(on: connection, buffer: pending)
        }
    }

    private func handle(_ line: String) {
        DispatchQueue.main.async { [weak self] in
            guard let self else { return }
            if line == "121" {
                self.textDocumentProxy.deleteBackward()
                self.statusLabel.text = "星蓝输入法 · 已退格"
                return
            }
            if line == "122" {
                self.textDocumentProxy.insertText("\n")
                self.statusLabel.text = "星蓝输入法 · 已回车"
                return
            }
            guard line.hasPrefix("11") else { return }
            let encoded = String(line.dropFirst(2))
            guard
                let data = Data(base64Encoded: encoded),
                let text = String(data: data, encoding: .utf8)
            else { return }
            self.textDocumentProxy.insertText(text)
            self.statusLabel.text = "星蓝输入法 · 已输入 \(text.count) 字"
        }
    }
}

