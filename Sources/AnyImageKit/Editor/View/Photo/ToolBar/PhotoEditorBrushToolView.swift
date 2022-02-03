//
//  PhotoEditorBrushToolView.swift
//  AnyImageKit
//
//  Created by 蒋惠 on 2022/1/22.
//  Copyright © 2022 AnyImageKit.org. All rights reserved.
//

import UIKit
import Combine

final class PhotoEditorBrushToolView: UIView {
    
    private var options: EditorPhotoOptionsInfo { viewModel.options }
    private let viewModel: PhotoEditorViewModel
    private var cancellable = Set<AnyCancellable>()
    
    private lazy var selectedIndex = options.brush.defaultColorIndex
    private var needLayout = false
    private var layoutWithAnimated = false
    
    private let colorWidth: CGFloat = 24
    private let itemWidth: CGFloat = 34
    private let minSpacing: CGFloat = 10
    private let maxCount: Int = 7
    private var optionsCount: Int { options.brush.colors.count }
    
    private let primaryGuide = UILayoutGuide()
    private let secondaryGuide = UILayoutGuide()
    
    private lazy var collectionView: ToolCollectionView = {
        let view = ToolCollectionView(items: createItems(), size: itemWidth, spacing: calculateSpacing())
        return view
    }()
    private lazy var undoButton: UIButton = {
        let view = UIButton(type: .custom)
        view.isEnabled = false
        view.setImage(options.theme[icon: .photoToolUndo], for: .normal)
        view.addTarget(self, action: #selector(undoButtonTapped(_:)), for: .touchUpInside)
        view.accessibilityLabel = options.theme[string: .undo]
        return view
    }()
    private lazy var slider: UISlider = {
        let view = UISlider(frame: .zero)
        view.isHidden = !options.brush.lineWidth.isDynamic
        view.alpha = 0.4
        view.minimumTrackTintColor = .white
        view.maximumTrackTintColor = .white.withAlphaComponent(0.5)
        view.value = options.brush.lineWidth.percent(of: options.brush.lineWidth.width)
        view.layer.applySketchShadow(color: .black.withAlphaComponent(0.4), alpha: 0.5, x: 0, y: 0, blur: 4, spread: 0)
        view.addTarget(self, action: #selector(sliderValueChanged(_:)), for: .valueChanged)
        view.addTarget(self, action: #selector(sliderTouchDown(_:)), for: .touchDown)
        view.addTarget(self, action: #selector(sliderTouchUp(_:)), for: [.touchUpInside, .touchUpOutside, .touchCancel])
        return view
    }()
    
    init(viewModel: PhotoEditorViewModel) {
        self.viewModel = viewModel
        super.init(frame: .zero)
        setupView()
        bindViewModel()
        updateSelectedStyle()
    }
    
    override func layoutSubviews() {
        super.layoutSubviews()
        guard needLayout else { return }
        needLayout = false
        UIView.animate(withDuration: layoutWithAnimated ? 0.25 : 0) {
            self.collectionView.spacing = self.calculateSpacing()
            self.collectionView.collectionView.reloadData()
        }
        layoutWithAnimated = false
    }
    
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }
    
    override func hitTest(_ point: CGPoint, with event: UIEvent?) -> UIView? {
        if isHidden || !isUserInteractionEnabled || alpha < 0.01 {
            return nil
        }
        for subView in subviews {
            if let hitView = subView.hitTest(subView.convert(point, from: self), with: event) {
                return hitView
            }
        }
        return nil
    }
}

// MARK: - Observer
extension PhotoEditorBrushToolView {
    
    private func bindViewModel() {
        viewModel.containerSizeSubject.sink { [weak self] _ in
            guard let self = self else { return }
            self.needLayout = true
        }.store(in: &cancellable)
        viewModel.traitCollectionSubject.sink { [weak self] traitCollection in
            guard let self = self else { return }
            self.layout()
            self.needLayout = true
            self.layoutWithAnimated = true
        }.store(in: &cancellable)
        
        viewModel.actionSubject.sink { [weak self] action in
            guard let self = self else { return }
            switch action {
            case .brushFinishDraw:
                self.undoButton.isEnabled = self.viewModel.stack.edit.brushCanUndo
            default:
                break
            }
        }.store(in: &cancellable)
    }
}

// MARK: - Target
extension PhotoEditorBrushToolView {
    
    @objc private func undoButtonTapped(_ sender: UIButton) {
        viewModel.send(action: .brushUndo)
        sender.isEnabled = viewModel.stack.edit.brushCanUndo
    }
    
    @objc private func colorButtonTapped(_ sender: UIButton) {
        if selectedIndex != sender.tag {
            selectedIndex = sender.tag
            updateSelectedStyle()
        }
        viewModel.send(action: .brushChangeColor(options.brush.colors[selectedIndex].color))
    }
    
    @available(iOS 14, *)
    @objc private func colorWellTapped(_ sender: ColorWell) {
        if selectedIndex != sender.tag {
            selectedIndex = sender.tag
            updateSelectedStyle()
        }
        viewModel.send(action: .brushChangeColor(sender.selectedColor ?? .white))
    }
    
    @available(iOS 14, *)
    @objc private func colorWellValueChanged(_ sender: ColorWell) {
        viewModel.send(action: .brushChangeColor(sender.selectedColor ?? .white))
    }
    
    @objc private func sliderValueChanged(_ sender: UISlider) {
        viewModel.send(action: .brushChangeLineWidth(options.brush.lineWidth.width(of: sender.value)))
    }
    
    @objc private func sliderTouchDown(_ sender: UISlider) {
        UIView.animate(withDuration: 0.2) {
            sender.alpha = 1.0
        }
    }
    
    @objc private func sliderTouchUp(_ sender: UISlider) {
        UIView.animate(withDuration: 0.2) {
            sender.alpha = 0.4
        }
    }
}

// MARK: - UI
extension PhotoEditorBrushToolView {
    
    private func setupView() {
        addLayoutGuide(primaryGuide)
        addLayoutGuide(secondaryGuide)
        
        addSubview(collectionView)
        addSubview(undoButton)
        addSubview(slider)
        
        layout()
    }
    
    private func layoutGuide() {
        layoutGuides.forEach { $0.snp.removeConstraints() }
        
        if viewModel.isRegular { // iPad
            primaryGuide.snp.remakeConstraints { make in
                make.trailing.equalToSuperview()
                make.centerY.equalToSuperview()
                make.width.equalTo(50)
                make.height.equalTo(calculateViewLength(count: optionsCount, maxCount: maxCount) + 10 + 44)
            }
            secondaryGuide.snp.remakeConstraints { make in
                make.top.bottom.equalTo(primaryGuide)
                make.leading.equalToSuperview()
                make.width.equalTo(primaryGuide)
            }
        } else { // iPhone
            primaryGuide.snp.remakeConstraints { make in
                make.bottom.leading.trailing.equalToSuperview()
                make.height.equalTo(50)
            }
            secondaryGuide.snp.remakeConstraints { make in
                make.top.leading.trailing.equalToSuperview()
                make.height.equalTo(primaryGuide)
            }
        }
    }
    
    private func layout() {
        subviews.forEach { $0.snp.removeConstraints() }
        layoutGuide()
        
        if viewModel.isRegular { // iPad
            collectionView.snp.remakeConstraints { make in
                make.top.equalTo(primaryGuide)
                make.bottom.equalTo(undoButton.snp.top).offset(-10)
                make.centerX.equalTo(primaryGuide)
                make.width.equalTo(itemWidth)
            }
            undoButton.snp.remakeConstraints { make in
                make.bottom.equalTo(primaryGuide)
                make.centerX.equalTo(primaryGuide)
                make.width.height.equalTo(44)
            }
            slider.transform = .identity.rotated(by: -(CGFloat.pi/2))
            slider.snp.remakeConstraints { make in
                make.width.equalTo(secondaryGuide.snp.height)
                make.center.equalTo(secondaryGuide)
            }
        } else { // iPhone
            collectionView.snp.remakeConstraints { make in
                make.leading.equalTo(primaryGuide).offset(15)
                make.trailing.equalTo(undoButton.snp.leading).offset(-15)
                make.centerY.equalTo(primaryGuide)
                make.height.height.equalTo(itemWidth)
            }
            undoButton.snp.remakeConstraints { make in
                make.trailing.equalTo(primaryGuide).offset(-15)
                make.centerY.equalTo(primaryGuide)
                make.width.height.equalTo(44)
            }
            slider.transform = .identity
            slider.snp.remakeConstraints { make in
                make.leading.trailing.equalTo(secondaryGuide).inset(15)
                make.centerY.equalTo(secondaryGuide)
            }
        }
    }
    
    private func updateSelectedStyle() {
        for (index, item) in collectionView.items.enumerated() {
            let scale: CGFloat = index == selectedIndex ? 1.25 : 1.0
            if let button = item as? ColorButton {
                button.colorView.transform = CGAffineTransform(scaleX: scale, y: scale)
                button.isSelected = index == selectedIndex
            }
            if #available(iOS 14.0, *) {
                if let colorWell = item as? ColorWell {
                    colorWell.transform = CGAffineTransform(scaleX: scale, y: scale)
                }
            }
        }
    }
    
    private func createItems() -> [UIView] {
        return options.brush.colors.enumerated().map { (idx, option) -> UIView in
            return createColorButton(idx: idx, option: option)
        }
    }
    
    private func createColorButton(idx: Int, option: EditorBrushColorOption) -> UIView {
        switch option {
        case .custom(let color):
            let button = ColorButton(tag: idx, size: colorWidth, color: color, borderWidth: 2, borderColor: UIColor.white)
            button.addTarget(self, action: #selector(colorButtonTapped(_:)), for: .touchUpInside)
            options.theme.buttonConfiguration[.brush(option)]?.configuration(button.colorView)
            return button
        case .colorWell(let color):
            if #available(iOS 14.0, *) {
                let colorWell = ColorWell(itemSize: colorWidth, borderWidth: 2)
                colorWell.backgroundColor = .clear
                colorWell.tag = idx
                colorWell.selectedColor = color
                colorWell.supportsAlpha = false
                colorWell.addTarget(self, action: #selector(colorWellTapped(_:)), for: .touchUpInside)
                colorWell.addTarget(self, action: #selector(colorWellValueChanged(_:)), for: .valueChanged)
                return colorWell
            } else {
                let button = ColorButton(tag: idx, size: colorWidth, color: color, borderWidth: 2, borderColor: UIColor.white)
                button.addTarget(self, action: #selector(colorButtonTapped(_:)), for: .touchUpInside)
                options.theme.buttonConfiguration[.brush(option)]?.configuration(button.colorView)
                return button
            }
        }
    }
    
    private func calculateViewLength(count: Int, maxCount: Int = 0) -> CGFloat {
        var optionsCount = CGFloat(count)
        let maxCount = CGFloat(maxCount)
        if maxCount > 0 {
            optionsCount = optionsCount > maxCount ? maxCount : optionsCount
        }
        return itemWidth * optionsCount + (optionsCount - 1) * minSpacing
    }
    
    private func calculateSpacing() -> CGFloat {
        var spacing: CGFloat = minSpacing
        let count = CGFloat(optionsCount)
        
        let maxSize: CGFloat
        if viewModel.isRegular { // iPad
            maxSize = primaryGuide.layoutFrame.height - 15 - 44
        } else { // iPhone
            maxSize = primaryGuide.layoutFrame.width - 15 - 15 - 44 - 15
        }
        
        if primaryGuide.layoutFrame == .zero {
            needLayout = true
        }

        if calculateViewLength(count: optionsCount) < maxSize {
            spacing = (maxSize - itemWidth * count) / (count - 1)
        }
        return spacing
    }
}
