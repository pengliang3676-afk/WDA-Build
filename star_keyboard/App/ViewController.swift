import UIKit

final class ViewController: UIViewController {
    override func viewDidLoad() {
        super.viewDidLoad()
        view.backgroundColor = UIColor(red: 0.04, green: 0.08, blue: 0.15, alpha: 1)

        let titleLabel = UILabel()
        titleLabel.text = "星蓝输入法"
        titleLabel.font = .boldSystemFont(ofSize: 30)
        titleLabel.textColor = .white
        titleLabel.textAlignment = .center

        let stepsLabel = UILabel()
        stepsLabel.text = """
        1. 打开“设置”
        2. 进入“通用 → 键盘 → 键盘”
        3. 点击“添加新键盘”
        4. 选择“星蓝输入法”
        5. 打开“允许完全访问”

        使用时切换到星蓝输入法。
        电脑通过 USB 发送的中文、英文和数字
        会直接进入当前输入框，不使用剪贴板。
        """
        stepsLabel.font = .systemFont(ofSize: 18)
        stepsLabel.textColor = UIColor(white: 0.9, alpha: 1)
        stepsLabel.numberOfLines = 0
        stepsLabel.textAlignment = .left

        let button = UIButton(type: .system)
        button.setTitle("打开键盘设置", for: .normal)
        button.titleLabel?.font = .boldSystemFont(ofSize: 18)
        button.setTitleColor(.white, for: .normal)
        button.backgroundColor = UIColor(red: 0.12, green: 0.56, blue: 0.96, alpha: 1)
        button.layer.cornerRadius = 10
        button.addTarget(self, action: #selector(openSettings), for: .touchUpInside)

        let stack = UIStackView(arrangedSubviews: [titleLabel, stepsLabel, button])
        stack.axis = .vertical
        stack.spacing = 28
        stack.translatesAutoresizingMaskIntoConstraints = false
        view.addSubview(stack)

        NSLayoutConstraint.activate([
            stack.leadingAnchor.constraint(equalTo: view.safeAreaLayoutGuide.leadingAnchor, constant: 28),
            stack.trailingAnchor.constraint(equalTo: view.safeAreaLayoutGuide.trailingAnchor, constant: -28),
            stack.centerYAnchor.constraint(equalTo: view.safeAreaLayoutGuide.centerYAnchor),
            button.heightAnchor.constraint(equalToConstant: 52)
        ])
    }

    @objc private func openSettings() {
        guard let url = URL(string: UIApplication.openSettingsURLString) else { return }
        UIApplication.shared.open(url)
    }
}

