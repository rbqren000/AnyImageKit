//
//  PhotoPreviewController.swift
//  AnyImageKit
//
//  Created by 蒋惠 on 2019/9/17.
//  Copyright © 2019-2022 AnyImageKit.org. All rights reserved.
//

import UIKit
import Photos

protocol PhotoPreviewControllerDataSource: AnyObject {
    
    typealias PreviewData = (thumbnail: UIImage?, asset: AssetOld)
    
    /// 获取需要展示图片的数量
    func numberOfPhotos(in controller: PhotoPreviewController) -> Int
    
    /// 获取索引对应的数据模型
    func previewController(_ controller: PhotoPreviewController, assetOfIndex index: Int) -> PreviewData
    
    /// 获取转场动画时的缩略图所在的 view
    func previewController(_ controller: PhotoPreviewController, thumbnailViewForIndex index: Int) -> UIView?
}

protocol PhotoPreviewControllerDelegate: AnyObject {
    
    /// 选择一张图片，需要返回所选图片的序号
    func previewController(_ controller: PhotoPreviewController, didSelected index: Int)
    
    /// 取消选择一张图片
    func previewController(_ controller: PhotoPreviewController, didDeselected index: Int)
    
    /// 开启/关闭原图
    func previewController(_ controller: PhotoPreviewController, useOriginalImage: Bool)
    
    /// 点击返回
    func previewControllerDidClickBack(_ controller: PhotoPreviewController)
    
    /// 点击完成
    func previewControllerDidClickDone(_ controller: PhotoPreviewController)
    
    /// 即将消失
    func previewControllerWillDisappear(_ controller: PhotoPreviewController)
}

extension PhotoPreviewControllerDelegate {
    func previewController(_ controller: PhotoPreviewController, didSelected index: Int) { }
    func previewController(_ controller: PhotoPreviewController, didDeselected index: Int) { }
    func previewController(_ controller: PhotoPreviewController, useOriginalImage: Bool) { }
    func previewControllerDidClickBack(_ controller: PhotoPreviewController) { }
    func previewControllerDidClickDone(_ controller: PhotoPreviewController) { }
}

final class PhotoPreviewController: AnyImageViewController, PickerOptionsConfigurable {
    
    weak var delegate: PhotoPreviewControllerDelegate?
    weak var dataSource: PhotoPreviewControllerDataSource?
    
    /// 图片索引
    var currentIndex: Int = 0 {
        didSet {
            didSetCurrentIdx()
        }
    }
    /// 左右两张图之间的间隙
    var photoSpacing: CGFloat = 30
    /// 图片缩放模式
    var imageScaleMode: UIView.ContentMode = .scaleAspectFill
    /// 双击放大图片时的目标比例
    var imageZoomScaleForDoubleTap: CGFloat = 2.0
    
    // MARK: - Private
    
    /// 当前正在显示视图的前一个页面关联视图
    private var relatedView: UIView? {
        return dataSource?.previewController(self, thumbnailViewForIndex: currentIndex)
    }
    /// 缩放型转场协调器
    private weak var scalePresentationController: ScalePresentationController?
    /// ToolBar 缩放动画前的状态
    private var toolBarHiddenStateBeforePan = false
    
    private lazy var flowLayout: UICollectionViewFlowLayout = makeFlowLayout()
    private(set) lazy var collectionView: UICollectionView = makeCollectionView()
    private(set) lazy var navigationBar: PickerPreviewNavigationBar = makeNavigationBar()
    private(set) lazy var toolBar: PickerToolBar = makeToolBar()
    private lazy var indexView: PickerPreviewIndexView = makeIndexView()
    
    let manager: PickerManager
    let photoLibrary: PhotoLibraryAssetCollection
    
    init(manager: PickerManager, photoLibrary: PhotoLibraryAssetCollection) {
        self.manager = manager
        self.photoLibrary = photoLibrary
        super.init(nibName: nil, bundle: nil)
        transitioningDelegate = self
        modalPresentationStyle = .custom
    }
    
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }
    
    // MARK: - Life Cycle
    
    override func viewDidLoad() {
        super.viewDidLoad()
        addNotifications()
        setupViews()
        update(options: manager.options)
    }
    
    override func viewWillAppear(_ animated: Bool) {
        super.viewWillAppear(animated)
        didSetCurrentIdx()
        setGIF(animated: true)
    }
    
    override func viewDidAppear(_ animated: Bool) {
        super.viewDidAppear(animated)
        setBar(hidden: false, animated: true)
    }
    
    override func viewDidLayoutSubviews() {
        super.viewDidLayoutSubviews()
        updateLayout()
    }
    
    override var prefersHomeIndicatorAutoHidden: Bool {
        return true
    }
    
    override var supportedInterfaceOrientations: UIInterfaceOrientationMask {
        return [.portrait]
    }
    
    override var preferredInterfaceOrientationForPresentation: UIInterfaceOrientation {
        return .portrait
    }
    
    override func setStatusBar(hidden: Bool) {
        if let controller = (presentingViewController as? AnyImageNavigationController)?.topViewController as? PhotoAssetCollectionViewController {
            controller.setStatusBar(hidden: hidden)
        }
    }
}

// MARK: - Private function
extension PhotoPreviewController {
    
    private func addNotifications() {
        NotificationCenter.default.addObserver(self, selector: #selector(containerSizeDidChange(_:)), name: .containerSizeDidChange, object: nil)
    }
}

// MARK: - UI Setup
extension PhotoPreviewController {
    
    private func setupViews() {
        view.backgroundColor = UIColor.clear
        collectionView.contentInsetAdjustmentBehavior = .never
        view.addSubview(collectionView)
        view.addSubview(navigationBar)
        view.addSubview(toolBar)
        view.addSubview(indexView)
        navigationBar.snp.makeConstraints { maker in
            maker.top.equalToSuperview()
            maker.left.right.equalToSuperview()
            maker.bottom.equalTo(view.safeAreaLayoutGuide.snp.top).offset(44)
        }
        toolBar.snp.makeConstraints { maker in
            maker.left.right.bottom.equalToSuperview()
            maker.top.equalTo(view.safeAreaLayoutGuide.snp.bottom).offset(-56)
        }
        indexView.snp.makeConstraints { maker in
            maker.left.right.equalToSuperview()
            maker.bottom.equalTo(toolBar.snp.top)
            maker.height.equalTo(96)
        }
        setBar(hidden: true, animated: false, isNormal: false)
    }
    
    private func makeFlowLayout() -> UICollectionViewFlowLayout {
        let layout = UICollectionViewFlowLayout()
        layout.scrollDirection = .horizontal
        return layout
    }
    
    private func makeCollectionView() -> UICollectionView {
        let view = UICollectionView(frame: .zero, collectionViewLayout: flowLayout)
        view.backgroundColor = .clear
        view.decelerationRate = .fast
        view.showsVerticalScrollIndicator = false
        view.showsHorizontalScrollIndicator = false
        view.isPagingEnabled = true
        view.alwaysBounceHorizontal = false
        view.isPrefetchingEnabled = false
        view.delegate = self
        view.dataSource = self
        view.registerCell(PreviewAssetPhotoCell.self)
        view.registerCell(PreviewAssetPhotoGIFCell.self)
        view.registerCell(PreviewAssetPhotoLiveCell.self)
        view.registerCell(PreviewAssetVideoCell.self)
        return view
    }
    
    private func makeNavigationBar() -> PickerPreviewNavigationBar {
        let view = PickerPreviewNavigationBar(frame: .zero)
        view.backButton.addTarget(self, action: #selector(backButtonTapped(_:)), for: .touchUpInside)
        view.selectButton.addTarget(self, action: #selector(selectButtonTapped(_:)), for: .touchUpInside)
        return view
    }
    
    private func makeToolBar() -> PickerToolBar {
        let view = PickerToolBar(style: .preview)
        view.originalButton.isSelected = manager.useOriginalImage
        view.leftButton.isHidden = true
        #if ANYIMAGEKIT_ENABLE_EDITOR
        view.leftButton.addTarget(self, action: #selector(editButtonTapped(_:)), for: .touchUpInside)
        #endif
        view.originalButton.addTarget(self, action: #selector(originalImageButtonTapped(_:)), for: .touchUpInside)
        view.doneButton.addTarget(self, action: #selector(doneButtonTapped(_:)), for: .touchUpInside)
        return view
    }
    
    private func makeIndexView() -> PickerPreviewIndexView {
        let view = PickerPreviewIndexView(frame: .zero)
        view.setManager(manager)
        view.isHidden = true
        view.delegate = self
        return view
    }
}

// MARK: - UI Update
extension PhotoPreviewController {
    
    /// 更新视图布局
    private func updateLayout() {
        flowLayout.minimumLineSpacing = photoSpacing
        flowLayout.itemSize = ScreenHelper.mainBounds.size
        collectionView.frame = ScreenHelper.mainBounds
        collectionView.frame.size.width = ScreenHelper.mainBounds.width + photoSpacing
        collectionView.contentInset = UIEdgeInsets(top: 0, left: 0, bottom: 0, right: photoSpacing)
    }
    
    /// 显示/隐藏工具栏
    private func setBar(hidden: Bool, animated: Bool = true, isNormal: Bool = true) {
        if navigationBar.alpha == 0 && hidden { return }
        if navigationBar.alpha == 1 && !hidden { return }
        if isNormal {
            setStatusBar(hidden: hidden)
            let color = UIColor.create(style: manager.options.theme.style,
                                       light: .white,
                                       dark: .black)
            scalePresentationController?.maskView.backgroundColor = hidden ? UIColor.black : color
        }
        
        UIView.animate(withDuration: animated ? 0.25 : 0) {
            self.navigationBar.alpha = hidden ? 0 : 1
            self.toolBar.alpha = hidden ? 0 : 1
            self.indexView.alpha = hidden ? 0 : 1
        }
    }
    
    /// 播放/暂停 GIF
    /// - Parameter animated: true-播放；false-暂停
    private func setGIF(animated: Bool) {
        for cell in collectionView.visibleCells {
            if let cell = cell as? PreviewAssetPhotoGIFCell {
                if animated {
                    cell.imageView.startAnimating()
                } else {
                    cell.imageView.stopAnimating()
                }
            }
        }
    }
    
    /// 暂停视频
    private func stopVideo() {
        for cell in collectionView.visibleCells {
            if let cell = cell as? PreviewAssetVideoCell {
                cell.pause()
            }
        }
    }
    
    private func didSetCurrentIdx() {
        guard let data = dataSource?.previewController(self, assetOfIndex: currentIndex) else { return }
        navigationBar.selectButton.isEnabled = true
        navigationBar.selectButton.setNum(data.asset.selectedNum, isSelected: data.asset.isSelected, animated: false)
        indexView.currentIndex = currentIndex
        
        if manager.options.allowUseOriginalImage {
            toolBar.originalButton.isHidden = data.asset.phAsset.mediaType != .image
        }
        #if ANYIMAGEKIT_ENABLE_EDITOR
        autoSetEditorButtonHidden()
        #endif
    }
}

// MARK: - Action
extension PhotoPreviewController {
    
    @objc private func containerSizeDidChange(_ sender: Notification) {
        collectionView.reloadData()
        let indexPath = IndexPath(item: currentIndex, section: 0)
        collectionView.scrollToItem(at: indexPath, at: .centeredHorizontally, animated: false)
    }
    
    /// NavigationBar - Back
    @objc private func backButtonTapped(_ sender: UIButton) {
        delegate?.previewControllerWillDisappear(self)
        dismiss(animated: true, completion: nil)
        setStatusBar(hidden: false)
        trackObserver?.track(event: .pickerBackInPreview, userInfo: [:])
    }
    
    /// NavigationBar - Select
    @objc func selectButtonTapped(_ sender: NumberCircleButton) {
        guard let data = dataSource?.previewController(self, assetOfIndex: currentIndex) else { return }
        let asset = data.asset
        
        if !asset.isSelected {
            let result = manager.addSelectedAsset(asset)
            if result.success {
                delegate?.previewController(self, didSelected: currentIndex)
            } else if !result.message.isEmpty {
                showAlert(message: result.message, stringConfig: manager.options.theme)
            }
        } else {
            manager.removeSelectedAsset(asset)
            delegate?.previewController(self, didDeselected: currentIndex)
        }
        
        navigationBar.selectButton.setNum(data.asset.selectedNum, isSelected: data.asset.isSelected, animated: true)
        indexView.didChangeSelectedAsset()
        trackObserver?.track(event: .pickerSelect, userInfo: [.isOn: data.asset.isSelected, .page: AnyImagePage.pickerPreview])
    }
    
    /// ToolBar - Original
    @objc private func originalImageButtonTapped(_ sender: UIButton) {
        sender.isSelected.toggle()
        manager.useOriginalImage = sender.isSelected
        delegate?.previewController(self, useOriginalImage: sender.isSelected)
        
        // 选择当前照片
        if manager.useOriginalImage && !manager.isUpToLimit {
            guard let data = dataSource?.previewController(self, assetOfIndex: currentIndex) else { return }
            if !data.asset.isSelected {
                selectButtonTapped(navigationBar.selectButton)
            }
        }
        trackObserver?.track(event: .pickerOriginalImage, userInfo: [.isOn: sender.isSelected, .page: AnyImagePage.pickerPreview])
    }
    
    /// ToolBar - Done
    @objc private func doneButtonTapped(_ sender: UIButton) {
        defer { sender.isEnabled = true }
        sender.isEnabled = false
        guard let data = dataSource?.previewController(self, assetOfIndex: currentIndex) else { return }
        if manager.selectedAssets.isEmpty {
            if case .disable(let rule) = data.asset.state {
                let message = rule.alertMessage(for: data.asset, assetList: manager.selectedAssets)
                showAlert(message: message, stringConfig: manager.options.theme)
                return
            }
            selectButtonTapped(navigationBar.selectButton)
        }
        delegate?.previewControllerWillDisappear(self)
        delegate?.previewControllerDidClickDone(self)
        trackObserver?.track(event: .pickerDone, userInfo: [.page: AnyImagePage.pickerPreview])
    }
}

// MARK: - UICollectionViewDataSource
extension PhotoPreviewController: UICollectionViewDataSource {
    
    func numberOfSections(in collectionView: UICollectionView) -> Int {
        return 1
    }
    
    func collectionView(_ collectionView: UICollectionView, numberOfItemsInSection section: Int) -> Int {
        return photoLibrary.assetCount
    }
    
    func collectionView(_ collectionView: UICollectionView, cellForItemAt indexPath: IndexPath) -> UICollectionViewCell {
        guard let asset = photoLibrary.loadAsset(for: indexPath.item) else { return UICollectionViewCell() }
        switch asset.mediaType {
        case .photo:
            let cell = collectionView.dequeueReusableCell(PreviewAssetPhotoCell.self, for: indexPath)
            cell.imageView.contentMode = imageScaleMode
            cell.imageZoomScaleForDoubleTap = imageZoomScaleForDoubleTap
            cell.tag = indexPath.item
            cell.manager = manager
            return cell
        case .photoGIF:
            let cell = collectionView.dequeueReusableCell(PreviewAssetPhotoGIFCell.self, for: indexPath)
            cell.tag = indexPath.item
            cell.manager = manager
            return cell
        case .photoLive:
            let cell = collectionView.dequeueReusableCell(PreviewAssetPhotoLiveCell.self, for: indexPath)
            cell.imageView.contentMode = imageScaleMode
            cell.tag = indexPath.item
            cell.manager = manager
            return cell
        case .video:
            let cell = collectionView.dequeueReusableCell(PreviewAssetVideoCell.self, for: indexPath)
            cell.imageView.contentMode = imageScaleMode
            cell.tag = indexPath.item
            return cell
        }
    }
}

// MARK: - UICollectionViewDelegate
extension PhotoPreviewController: UICollectionViewDelegate {
    
    /// Cell 进入屏幕 - 请求数据
    func collectionView(_ collectionView: UICollectionView, willDisplay cell: UICollectionViewCell, forItemAt indexPath: IndexPath) {
        guard let asset = photoLibrary.loadAsset(for: indexPath.item) else { return }
        if let cell = cell as? PreviewAssetCell {
            cell.setContent(asset: asset)
        }
    }
    
    /// Cell 离开屏幕 - 重设状态
    func collectionView(_ collectionView: UICollectionView, didEndDisplaying cell: UICollectionViewCell, forItemAt indexPath: IndexPath) {
        if let cell = cell as? PreviewAssetCell {
            cell.reset()
        }
    }
}

// MARK: - UIScrollViewDelegate
extension PhotoPreviewController: UIScrollViewDelegate {
    
    /// 开始滑动 - 停止 GIF 和视频
    func scrollViewWillBeginDragging(_ scrollView: UIScrollView) {
        setGIF(animated: false)
        stopVideo()
    }
    
    /// 停止滑动 - 开始 GIF
    func scrollViewDidEndDecelerating(_ scrollView: UIScrollView) {
        setGIF(animated: true)
    }
    
    func scrollViewDidScroll(_ scrollView: UIScrollView) {
        if scrollView.contentSize.width - scrollView.contentOffset.x < scrollView.bounds.width { return } // isLast
        var idx = Int(scrollView.contentOffset.x / scrollView.bounds.width)
        let x = scrollView.contentOffset.x.truncatingRemainder(dividingBy: scrollView.bounds.width)
        if x > scrollView.bounds.width / 2 {
            idx += 1
        }
        if idx != currentIndex {
            currentIndex = idx
        }
    }
}

/*
// MARK: - PreviewAssetCellDelegate
extension PhotoPreviewController: PreviewAssetCellDelegate {
    
    func previewCellDidBeginPan(_ cell: PreviewAssetCell) {
        delegate?.previewControllerWillDisappear(self)
        toolBarHiddenStateBeforePan = navigationBar.alpha == 0
    }
    
    func previewCell(_ cell: PreviewAssetCell, didPanScale scale: CGFloat) {
        // 实测用 scale 的平方，效果比线性好些
        let alpha = scale * scale
        scalePresentationController?.maskAlpha = alpha
        setBar(hidden: true, isNormal: false)
    }
    
    func previewCell(_ cell: PreviewAssetCell, didEndPanWithExit isExit: Bool) {
        if isExit {
            dismiss(animated: true, completion: nil)
            setStatusBar(hidden: false)
        } else if !toolBarHiddenStateBeforePan {
            setBar(hidden: false, isNormal: false)
        }
    }
    
    func previewCellDidSingleTap(_ cell: PreviewAssetCell) {
        setBar(hidden: navigationBar.alpha == 1, animated: false)
    }
    
    func previewCellGetToolBarHiddenState() -> Bool {
        return navigationBar.alpha == 0
    }
}
*/
// MARK: - PickerPreviewIndexViewDelegate
extension PhotoPreviewController: PickerPreviewIndexViewDelegate {
    
    func pickerPreviewIndexView(_ view: PickerPreviewIndexView, didSelect idx: Int) {
        currentIndex = idx
        collectionView.scrollToItem(at: IndexPath(item: idx, section: 0), at: .left, animated: false)
        #if ANYIMAGEKIT_ENABLE_EDITOR
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) { [weak self] in
            self?.autoSetEditorButtonHidden()
        }
        #endif
    }
}

// MARK: - UIViewControllerTransitioningDelegate
extension PhotoPreviewController: UIViewControllerTransitioningDelegate {
    /// 提供进场动画
    func animationController(forPresented presented: UIViewController, presenting: UIViewController, source: UIViewController) -> UIViewControllerAnimatedTransitioning? {
        updateLayout()
        // 立即加载collectionView
        let indexPath = IndexPath(item: currentIndex, section: 0)
        collectionView.reloadData()
        collectionView.scrollToItem(at: indexPath, at: .left, animated: false)
        collectionView.layoutIfNeeded()
        return makeScalePresentationAnimator(indexPath: indexPath)
    }
    
    /// 提供退场动画
    func animationController(forDismissed dismissed: UIViewController) -> UIViewControllerAnimatedTransitioning? {
        return makeDismissedAnimator()
    }
    
    /// 提供转场协调器
    func presentationController(forPresented presented: UIViewController, presenting: UIViewController?, source: UIViewController) -> UIPresentationController? {
        let controller = ScalePresentationController(presentedViewController: presented, presenting: presenting)
        let color = UIColor.create(style: manager.options.theme.style,
                                   light: .white,
                                   dark: .black)
        controller.maskView.backgroundColor = color
        scalePresentationController = controller
        return controller
    }
    
    /// 创建缩放型进场动画
    private func makeScalePresentationAnimator(indexPath: IndexPath) -> UIViewControllerAnimatedTransitioning {
        let cell = collectionView.cellForItem(at: indexPath) as? PreviewAssetCell
        let imageView = UIImageView(image: cell?.imageView.image)
        imageView.contentMode = imageScaleMode
        imageView.clipsToBounds = true
        // 创建animator
        return ScaleAnimator(startView: relatedView, endView: cell?.imageView, scaleView: imageView)
    }
    
    /// 创建缩放型退场动画
    private func makeDismissedAnimator() -> UIViewControllerAnimatedTransitioning? {
        guard let cell = collectionView.visibleCells.first as? PreviewAssetCell else {
            return nil
        }
        let imageView = UIImageView(image: cell.imageView.image)
        imageView.contentMode = imageScaleMode
        imageView.clipsToBounds = true
        return ScaleAnimator(startView: cell.imageView, endView: relatedView, scaleView: imageView)
    }
}
