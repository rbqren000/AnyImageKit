//
//  PreviewAssetPhotoCell.swift
//  AnyImageKit
//
//  Created by 蒋惠 on 2019/9/17.
//  Copyright © 2019-2022 AnyImageKit.org. All rights reserved.
//

import UIKit
import Photos

final class PreviewAssetPhotoCell: PreviewAssetCell {
    
    /// 双击放大图片时的目标比例
    var imageZoomScaleForDoubleTap: CGFloat = 2.0
    
    /// 双击手势
    private lazy var doubleTap: UITapGestureRecognizer = makeDoubleTap()
    
    private var task: Task<Void, Error>?
    
    override init(frame: CGRect) {
        super.init(frame: frame)
        setupView()
    }
    
    required init?(coder aDecoder: NSCoder) {
        super.init(coder: aDecoder)
        setupView()
    }
    
    override func prepareForReuse() {
        super.prepareForReuse()
        task?.cancel()
        task = nil
    }
    
    /// 重置图片缩放比例
    func reset() {
        scrollView.setZoomScale(scrollView.minimumZoomScale, animated: false)
    }
    
    override func optionsDidUpdate(options: PickerOptionsInfo) {
        accessibilityLabel = options.theme[string: .photo]
    }
    
    override func setContent(asset: Asset<PHAsset>) {
        task?.cancel()
        task = Task {
            do {
                try await loadImage(asset: asset)
            } catch {
                _print(error)
            }
        }
    }
}

// MARK: UI Setup
extension PreviewAssetPhotoCell {
    
    private func setupView() {
        scrollView.delegate = self
        contentView.addGestureRecognizer(doubleTap)
        singleTap.require(toFail: doubleTap)
    }
    
    private func makeDoubleTap() -> UITapGestureRecognizer {
        let gesture = UITapGestureRecognizer(target: self, action: #selector(onDoubleTap(_:)))
        gesture.numberOfTapsRequired = 2
        return gesture
    }
}

// MARK: - Content Setup
extension PreviewAssetPhotoCell {
    
    private func loadImage(asset: Asset<PHAsset>) async throws {
        for try await result in asset.loadImage() {
            switch result {
            case .progress(let progress):
                updateLoadingProgress(progress)
            case .success(let loadResult):
                switch loadResult {
                case .thumbnail(let image):
                    setImage(image)
                case .preview(let image):
                    updateLoadingProgress(1.0)
                    setImage(image)
                default:
                    break
                }
            }
        }
    }
}

// MARK: - Action
extension PreviewAssetPhotoCell {
    
    @objc private func onDoubleTap(_ gesture: UITapGestureRecognizer) {
        // 如果当前没有任何缩放，则放大到目标比例
        // 否则重置到原比例
        if scrollView.zoomScale == 1.0 {
            if scrollView.minimumZoomScale == scrollView.zoomScale {
                // 以点击的位置为中心，放大
                let pointInView = gesture.location(in: imageView)
                let w = scrollView.bounds.size.width / imageZoomScaleForDoubleTap
                let h = scrollView.bounds.size.height / imageZoomScaleForDoubleTap
                let x = pointInView.x - (w / 2.0)
                let y = pointInView.y - (h / 2.0)
                scrollView.zoom(to: CGRect(x: x, y: y, width: w, height: h), animated: true)
            } else {
                scrollView.setZoomScale(scrollView.minimumZoomScale, animated: true)
            }
        } else if scrollView.zoomScale == scrollView.minimumZoomScale {
            scrollView.setZoomScale(1.0, animated: true)
        } else {
            scrollView.setZoomScale(scrollView.minimumZoomScale, animated: true)
        }
    }
}

// MARK: - UIScrollViewDelegate
extension PreviewAssetPhotoCell: UIScrollViewDelegate {
    
    func viewForZooming(in scrollView: UIScrollView) -> UIView? {
        return imageView
    }
    
    func scrollViewDidZoom(_ scrollView: UIScrollView) {
        imageView.center = centerOfContentSize
    }
}
