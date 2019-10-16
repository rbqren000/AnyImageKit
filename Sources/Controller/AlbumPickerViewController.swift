//
//  AlbumPickerViewController.swift
//  AnyImagePicker
//
//  Created by 刘栋 on 2019/9/16.
//  Copyright © 2019 anotheren.com. All rights reserved.
//

import UIKit

private let rowHeight: CGFloat = 55

protocol AlbumPickerViewControllerDelegate: class {
    
    func albumPicker(_ picker: AlbumPickerViewController, didSelected album: Album)
    func albumPickerWillDisappear()
}

final class AlbumPickerViewController: UIViewController {
    
    weak var delegate: AlbumPickerViewControllerDelegate?
    var album: Album?
    var albums = [Album]()
    
    private lazy var tableView: UITableView = {
        let view = UITableView(frame: .zero, style: .plain)
        view.registerCell(AlbumCell.self)
        view.backgroundColor = PhotoManager.shared.config.theme.backgroundColor
        view.separatorStyle = .none
        view.dataSource = self
        view.delegate = self
        return view
    }()
    
    override func viewDidLoad() {
        super.viewDidLoad()
        updatePreferredContentSize(with: traitCollection)
        setupView()
    }
    
    override func viewWillDisappear(_ animated: Bool) {
        super.viewWillDisappear(animated)
        delegate?.albumPickerWillDisappear()
    }
    
    override public func willTransition(to newCollection: UITraitCollection, with coordinator: UIViewControllerTransitionCoordinator) {
        super.willTransition(to: newCollection, with: coordinator)
        updatePreferredContentSize(with: newCollection)
    }
    
    private func updatePreferredContentSize(with traitCollection: UITraitCollection) {
        let size = UIScreen.main.bounds.size
        let height = CGFloat(albums.count) * rowHeight
        let preferredMinHeight = rowHeight * 5
        let preferredMaxHeight = size.height*(2.0/3.0)
        preferredContentSize = CGSize(width: size.width, height: max(preferredMinHeight, min(height, preferredMaxHeight)))
    }
}

// MARK: - Action

extension AlbumPickerViewController {
    
    @objc private func cancelButtonTapped(_ sender: UIBarButtonItem) {
        dismiss(animated: true, completion: nil)
    }
}


// MARK: - Private

extension AlbumPickerViewController {
    
    private func setupView() {
        view.addSubview(tableView)
        tableView.snp.makeConstraints { maker in
            maker.edges.equalTo(view.snp.edges)
        }
    }
}

// MARK: - UITableViewDataSource

extension AlbumPickerViewController: UITableViewDataSource {
    
    func numberOfSections(in tableView: UITableView) -> Int {
        return 1
    }
    
    func tableView(_ tableView: UITableView, numberOfRowsInSection section: Int) -> Int {
        return albums.count
    }
    
    func tableView(_ tableView: UITableView, cellForRowAt indexPath: IndexPath) -> UITableViewCell {
        let cell = tableView.dequeueReusableCell(AlbumCell.self, for: indexPath)
        let album = albums[indexPath.row]
        cell.setContent(album)
        cell.accessoryType = self.album == album ? .checkmark : .none
        return cell
    }
}

// MARK: - UITableViewDelegate

extension AlbumPickerViewController: UITableViewDelegate {
    
    func tableView(_ tableView: UITableView, didSelectRowAt indexPath: IndexPath) {
        let album = albums[indexPath.row]
        delegate?.albumPicker(self, didSelected: album)
        dismiss(animated: true, completion: nil)
        tableView.deselectRow(at: indexPath, animated: true)
    }
    
    func tableView(_ tableView: UITableView, heightForRowAt indexPath: IndexPath) -> CGFloat {
        return rowHeight
    }
}
