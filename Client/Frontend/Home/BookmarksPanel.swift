/* This Source Code Form is subject to the terms of the Mozilla Public
 * License, v. 2.0. If a copy of the MPL was not distributed with this
 * file, You can obtain one at http://mozilla.org/MPL/2.0/. */

import UIKit
import Storage
import Shared
import XCGLogger

private let log = Logger.browserLogger

let BookmarkStatusChangedNotification = "BookmarkStatusChangedNotification"

// MARK: - Placeholder strings for Bug 1232810.

let deleteWarningTitle = NSLocalizedString("This folder isn't empty.", tableName: "BookmarkPanelDeleteConfirm", comment: "Title of the confirmation alert when the user tries to delete a folder that still contains bookmarks and/or folders.")
let deleteWarningDescription = NSLocalizedString("Are you sure you want to delete it and its contents?", tableName: "BookmarkPanelDeleteConfirm", comment: "Main body of the confirmation alert when the user tries to delete a folder that still contains bookmarks and/or folders.")
let deleteCancelButtonLabel = NSLocalizedString("Cancel", tableName: "BookmarkPanelDeleteConfirm", comment: "Button label to cancel deletion when the user tried to delete a non-empty folder.")
let deleteDeleteButtonLabel = NSLocalizedString("Delete", tableName: "BookmarkPanelDeleteConfirm", comment: "Button label for the button that deletes a folder and all of its children.")

// Placeholder strings for Bug 1248034
let emptyBookmarksText = NSLocalizedString("Bookmarks you save will show up here.", comment: "Status label for the empty Bookmarks state.")

// MARK: - UX constants.

struct BookmarksPanelUX {
    fileprivate static let BookmarkFolderHeaderViewChevronInset: CGFloat = 10
    fileprivate static let BookmarkFolderChevronSize: CGFloat = 20
    fileprivate static let BookmarkFolderChevronLineWidth: CGFloat = 4.0
    fileprivate static let BookmarkFolderTextColor = UIColor(red: 92/255, green: 92/255, blue: 92/255, alpha: 1.0)
    fileprivate static let WelcomeScreenPadding: CGFloat = 15
    fileprivate static let WelcomeScreenItemTextColor = UIColor.gray
    fileprivate static let WelcomeScreenItemWidth = 170
    fileprivate static let SeparatorRowHeight: CGFloat = 0.5
}

public extension UIBarButtonItem {
    
    public class func createImageButtonItem(_ image:UIImage, action:Selector) -> UIBarButtonItem {
        let button = UIButton(type: .custom)
        button.frame = CGRect(x: 0, y: 0, width: image.size.width, height: image.size.height)
        button.addTarget(self, action: action, for: .touchUpInside)
        button.setImage(image, for: UIControlState())
        
        return UIBarButtonItem(customView: button)
    }
    
    public class func createFixedSpaceItem(_ width:CGFloat) -> UIBarButtonItem {
        let item = UIBarButtonItem(barButtonSystemItem: .fixedSpace, target: self, action: nil)
        item.width = width
        return item
    }
}

@objc class BookmarkFoldersPickerDataSource : NSObject, UIPickerViewDataSource, UIPickerViewDelegate {
    var folders:[BookmarkFolder] = [BookmarkFolder]()
    var componentWidth:CGFloat = 300
    var rowHeight:CGFloat = 60
    
    override init() {
        
    }
    
    func addFolder(_ folder:BookmarkFolder) {
        folders.append(folder)
    }
    
    func numberOfComponents(in pickerView: UIPickerView) -> Int {
        return 1
    }
    func pickerView(_ pickerView: UIPickerView, numberOfRowsInComponent component: Int) -> Int {
        return folders.count
    }
    
    func pickerView(_ pickerView: UIPickerView, widthForComponent component: Int) -> CGFloat {
        return componentWidth
    }
    
    func pickerView(_ pickerView: UIPickerView, rowHeightForComponent component: Int) -> CGFloat {
        return 18
    }
    
    func pickerView(_ pickerView: UIPickerView, viewForRow row: Int, forComponent component: Int, reusing view: UIView?) -> UIView {
        var rowView:UILabel! = view as? UILabel
        if rowView == nil {
            rowView = UILabel()
            rowView.font = UIFont.systemFont(ofSize: 13)
            rowView.text = folders[row].title
        }
        return rowView
    }
    
    func pickerView(_ pickerView: UIPickerView, titleForRow row: Int, forComponent component: Int) -> String? {
        return folders[row].title
    }
}

class BkPopoverControllerDelegate : NSObject, UIPopoverPresentationControllerDelegate {
    func adaptivePresentationStyle(for controller: UIPresentationController) -> UIModalPresentationStyle {
        return .none;
    }
}

class BorderedButton: UIButton {
    let buttonBorderColor = UIColor.lightGray
    
    override init(frame: CGRect) {
        super.init(frame: frame)
        
        layer.borderColor = buttonBorderColor.cgColor
        layer.borderWidth = 0.5
        
        contentEdgeInsets = UIEdgeInsets(top: 7, left: 10, bottom: 7, right: 10)
    }
    
    required init?(coder aDecoder: NSCoder) {
        fatalError("not implemented")
    }
    
    override var isHighlighted: Bool {
        didSet {
            let fadedColor = buttonBorderColor.withAlphaComponent(0.2).cgColor
            
            if isHighlighted {
                layer.borderColor = fadedColor
            } else {
                layer.borderColor = buttonBorderColor.cgColor
                
                let animation = CABasicAnimation(keyPath: "borderColor")
                animation.fromValue = fadedColor
                animation.toValue = buttonBorderColor.cgColor
                animation.duration = 0.4
                layer.add(animation, forKey: "")
            }
        }
    }
}

class BookmarkEditViewController : UIViewController {
    var completionBlock:(() -> Void)?
    var sourceTable:UITableView!
    var sourceCell:UITableViewCell!
    var folderPickerDataSource:BookmarkFoldersPickerDataSource!
    var nameTextField:UITextField!
    var urlValue:UITextField!
    var folderPicker:UIPickerView!
    var okButton:UIButton!
    var cancelButton:UIButton!

    var dialogHeight:CGFloat = 200
    
    var bookmarksPanel:BookmarksPanel!
    var bookmark:BookmarkItem!
    var currentFolderGUID:String!
    var bookmarkIndexPath:IndexPath!
    
    init(sourceTable table:UITableView!, sourceCell cell:UITableViewCell!, indexPath:IndexPath, currentFolderGUID:String, bookmarksPanel:BookmarksPanel, bookmark:BookmarkItem!, folderPickerDataSource:BookmarkFoldersPickerDataSource) {
        super.init(nibName: nil, bundle: nil)
        sourceTable = table
        sourceCell = cell
        
        let targetWidth = sourceTable.bounds.width * 0.8
        
        if UIDevice.currentDevice().userInterfaceIdiom == UIUserInterfaceIdiom.Phone {
            self.modalPresentationStyle = .OverCurrentContext //.Popover
            self.modalTransitionStyle = .CoverVertical
            self.preferredContentSize = UIScreen.mainScreen().bounds.size
        }
        else {
            self.modalPresentationStyle = .Popover
            self.preferredContentSize = CGSize(width: targetWidth, height: dialogHeight)
            self.popoverPresentationController!.delegate = BkPopoverControllerDelegate()
        }
    
        self.folderPickerDataSource = folderPickerDataSource
        self.bookmark = bookmark
        self.bookmarksPanel = bookmarksPanel
        self.bookmarkIndexPath = indexPath
        self.currentFolderGUID = currentFolderGUID
    }
    
    required init?(coder aDecoder: NSCoder) {
        super.init(coder: aDecoder)
    }
    
    func folderDataForGUID(_ guid:String) -> (guid:String, title:String, position:Int)? {
        var position = 0
        for item in folderPickerDataSource.folders {
            if item.guid == guid {
                return (guid: item.guid, title:item.title, position: position)
            }
            position += 1
        }
        return nil
    }
    
    override func viewDidLoad() {
        super.viewDidLoad()
        self.view.addGestureRecognizer(UITapGestureRecognizer(target: self, action: #selector(onTap)))
        
        let targetWidth = sourceTable.bounds.width * 0.8

        let dataContainer = UIView()
        
        let mainView = UIView()
        mainView.frame = CGRect(x: 0, y: 0, width: targetWidth, height: dialogHeight)
        mainView.layer.cornerRadius = 8
        mainView.layer.masksToBounds = true

        if UIDevice.current.userInterfaceIdiom == UIUserInterfaceIdiom.phone {
            var point = view.center
            //iPhone correction for the border - TODO calculate based on table
            point.x = point.x - 20
            mainView.center = view.center
            dataContainer.frame = CGRect(x: 0, y: 0, width: targetWidth, height: dialogHeight-40)
        }
        else {
            dataContainer.frame = CGRect(x: 10, y: 0, width: targetWidth-20, height: dialogHeight-40)
        }
        
        let dataWidth = dataContainer.frame.size.width
        mainView.backgroundColor = UIColor(white: 1, alpha: 0.98)
        mainView.isOpaque = true
        
        dataContainer.backgroundColor = UIColor.clear
        mainView.addSubview(dataContainer)
        view.addSubview(mainView)
        view.backgroundColor =  UIColor(white: 0.2, alpha: 0.8)
        
        mainView.addGestureRecognizer(UITapGestureRecognizer(target: self, action: #selector(onTap)))

        if let popover = self.popoverPresentationController {
            popover.permittedArrowDirections = .any
            popover.sourceView = sourceCell
            popover.sourceRect = sourceCell.bounds
            popover.popoverLayoutMargins = UIEdgeInsetsMake(0, 0, 0, 0)
        }
        
        let margin:CGFloat = 10
        let labelWidth:CGFloat = 50
        let rowHeight:CGFloat = 20
//        let textFieldWidth = CGFloat(targetWidth) - CGFloat(margin*2) - CGFloat(5) - labelWidth
        
        let nameLabel:UILabel = UILabel()
        nameLabel.font = UIFont.boldSystemFont(ofSize: 13)
        nameLabel.textColor = UIColor.black
        nameLabel.text = "Edit Bookmark"
        nameLabel.frame = CGRect(x: 0, y: margin, width: dataWidth, height: rowHeight)
        nameLabel.textAlignment = NSTextAlignment.center
        
        
        let textLabel:UILabel = UILabel()
        textLabel.font = UIFont.boldSystemFont(ofSize: 10)
        textLabel.text = "Title"
        textLabel.textColor = UIColor.gray
        textLabel.frame = CGRect(x: 10, y: 2, width: 40, height: 15)

        
        nameTextField = UITextField()
        nameTextField.backgroundColor = UIColor.white
        nameTextField.layer.borderWidth = 0.5
        nameTextField.layer.borderColor = UIColor.lightGray.cgColor
        nameTextField.font = UIFont.systemFont(ofSize: 13)

        nameTextField.leftViewMode = .always
        nameTextField.leftView = textLabel
        nameTextField.clearButtonMode = .whileEditing
        
        nameTextField.frame = CGRect(x: 0, y: 40, width: dataWidth, height: rowHeight)
        nameTextField.text = bookmark.title
        
        let urlLabel:UILabel = UILabel()
        urlLabel.font = UIFont.boldSystemFont(ofSize: 10)
        urlLabel.text = "URL"
        urlLabel.textColor = UIColor.lightGray
        urlLabel.frame = CGRect(x: 10, y: 2, width: 40, height: 15)

        urlValue = UITextField()
        urlValue.font = UIFont.systemFont(ofSize: 11)
        urlValue.leftViewMode = .always
        urlValue.leftView = urlLabel
        urlValue.textColor = UIColor.gray
        urlValue.frame = CGRect(x: 0, y: 60, width: dataWidth, height: rowHeight)
        urlValue.text = bookmark.url
        
        let folderLabel:UILabel = UILabel()
        folderLabel.font = UIFont.boldSystemFont(ofSize: 10)
        folderLabel.text = "Folder"
        folderLabel.textColor = UIColor.gray
        folderLabel.frame = CGRect(x: 0, y: (margin*3)+(rowHeight*2)+10, width: labelWidth, height: rowHeight)
        folderPicker = UIPickerView()
        
        folderPicker.frame = CGRect(x: 0, y: (margin*3)+(rowHeight*2)+20, width: dataWidth, height: 60)
//        folderPicker.frame = CGRect(x: margin*2, y: (margin*4)+(rowHeight*3), width: targetWidth*0.8, height: 60)

        self.folderPickerDataSource.componentWidth = targetWidth*0.8
        folderPicker.dataSource = self.folderPickerDataSource
        folderPicker.delegate = self.folderPickerDataSource
        
        if let data = folderDataForGUID(currentFolderGUID) {
            folderPicker.selectRow(data.position, inComponent: 0, animated: true)
        }
        
        dataContainer.addSubview(nameLabel)
        dataContainer.addSubview(nameTextField)
        dataContainer.addSubview(urlValue)
        dataContainer.addSubview(folderLabel)
        dataContainer.addSubview(folderPicker)
        
        let middle:CGFloat = targetWidth/2
        
        
        okButton = BorderedButton(type: .system)
        okButton.setTitle("OK", for: UIControlState())
        okButton.frame = CGRect(x: middle, y: dialogHeight-39, width: middle, height: 40)
        okButton.addTarget(self, action: #selector(onOkPressed), for: .touchUpInside)
        
        cancelButton = BorderedButton(type: .system)
        cancelButton.tintColor = UIColor.darkGray
        cancelButton.frame = CGRect(x: -1, y: dialogHeight-39, width: middle+1, height: 40)
        cancelButton.setTitle("Cancel", for: UIControlState())
        cancelButton.addTarget(self, action: #selector(onCancelPressed), for: .touchUpInside)

        mainView.addSubview(okButton)
        mainView.addSubview(cancelButton)
    }
    
    func onOkPressed() {
        //save & dismiss
        if let possibleNewTitle = nameTextField.text  {
            var newTitle:String! = possibleNewTitle.trimmingCharacters(in: CharacterSet.whitespacesAndNewlines)
            let folderGUID = folderPickerDataSource.folders[folderPicker.selectedRowInComponent(0)].guid as String
            
            let newFolderGUID:String? = (folderGUID == currentFolderGUID) ? nil : folderGUID

            if newTitle.characters.count == 0 {
                //TODO error
                return
            }
            
            if newTitle == bookmark.title && newFolderGUID == nil {
                //nothing to change in this case
                return
            }
            newTitle = (newTitle == bookmark.title) ? nil : newTitle
            
            bookmarksPanel.editBookmark(bookmark, newTitle: newTitle, newFolderGUID: newFolderGUID, atIndexPath: bookmarkIndexPath)
            NotificationCenter.defaultCenter.postNotificationName(BookmarkStatusChangedNotification, object: bookmark, userInfo:["added": false])
        }
        self.dismiss()
    }

    func onCancelPressed() {
        //dismiss
        self.dismiss()
    }
    
    func onTap(_ recognizer: UITapGestureRecognizer) {
        if recognizer.view == self.view {
            self.dismiss()
        }
    }
    
    func dismiss() {
        self.dismiss(animated: true, completion: completionBlock)
    }
}

class BookmarksPanel: SiteTableViewController, HomePanel {
    weak var homePanelDelegate: HomePanelDelegate? = nil
    var source: BookmarksModel?
    var parentFolders = [BookmarkFolder]()
    var bookmarkFolder: BookmarkFolder? {
        didSet {
            if let folder = bookmarkFolder {
                self.title = folder.title
            }
        }
    }
    var folderPicker:BookmarkFoldersPickerDataSource!
    
    var currentItemCount:Int {
        return source?.current.count ?? 0
    }
    var orderedBookmarkGUIDs:[String] = [String]()
    var orderUpdatedBookmarkGUIDs:[String] = [String]()

    fileprivate let BookmarkFolderCellIdentifier = "BookmarkFolderIdentifier"
    fileprivate let BookmarkSeparatorCellIdentifier = "BookmarkSeparatorIdentifier"
    fileprivate let BookmarkFolderHeaderViewIdentifier = "BookmarkFolderHeaderIdentifier"

    var editBookmarksToolbar:UIToolbar!

    var editBookmarksButton:UIBarButtonItem!
    var addRemoveFolderButton:UIBarButtonItem!
    var removeFolderButton:UIBarButtonItem!
    var addFolderButton:UIBarButtonItem!

    init() {
        super.init(nibName: nil, bundle: nil)
        self.title = "Bookmarks"
        NotificationCenter.defaultCenter().addObserver(self, selector: #selector(BookmarksPanel.notificationReceived(_:)), name: NotificationFirefoxAccountChanged, object: nil)

        self.tableView.register(SeparatorTableCell.self, forCellReuseIdentifier: BookmarkSeparatorCellIdentifier)
        self.tableView.register(BookmarkFolderTableViewCell.self, forCellReuseIdentifier: BookmarkFolderCellIdentifier)
        self.tableView.register(BookmarkFolderTableViewHeader.self, forHeaderFooterViewReuseIdentifier: BookmarkFolderHeaderViewIdentifier)
    }

    required init?(coder aDecoder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    deinit {
        NotificationCenter.defaultCenter().removeObserver(self, name: NotificationFirefoxAccountChanged, object: nil)
    }
    
    override func viewDidLoad() {
        super.viewDidLoad()
        
        let width = self.view.bounds.size.width
        let toolbarHeight = CGFloat(44)
        editBookmarksToolbar = UIToolbar(frame: CGRect(x: 0, y: 0, width: width, height: toolbarHeight))
        createEditBookmarksToolbar()
        editBookmarksToolbar.barTintColor = UIColor(white: 225/255.0, alpha: 1.0)
        
        self.view.addSubview(editBookmarksToolbar)
        
        editBookmarksToolbar.snp_makeConstraints { make in
            make.height.equalTo(toolbarHeight)
            make.left.equalTo(self.view)
            make.right.equalTo(self.view)
            make.bottom.equalTo(self.view)
            return
        }
        
        tableView.snp_makeConstraints { make in
            make.bottom.equalTo(view).inset(UIEdgeInsetsMake(0, 0, toolbarHeight, 0))
            return
        }
        
        // If we've not already set a source for this panel, fetch a new model from
        // the root; otherwise, just use the existing source to select a folder.
        guard let source = self.source else {
            // Get all the bookmarks split by folders
            if let bookmarkFolder = bookmarkFolder {
                profile.bookmarks.modelFactory >>== { $0.modelForFolder(bookmarkFolder).upon(self.onModelFetched) }
            } else {
                profile.bookmarks.modelFactory >>== { $0.modelForRoot().upon(self.onModelFetched) }
            }
            return
        }

        if let bookmarkFolder = bookmarkFolder {
            source.selectFolder(bookmarkFolder).upon(onModelFetched)
        } else {
            source.selectFolder(BookmarkRoots.MobileFolderGUID).upon(onModelFetched)
        }
    }
    
    func disableTableEditingMode() {
        DispatchQueue.main.async {
            if self.tableView.isEditing {
                self.switchTableEditingMode()
            }
        }
    }
    
    var bookmarksOrderChanged:Bool {
        return orderedBookmarkGUIDs != orderUpdatedBookmarkGUIDs
    }
    
    func switchTableEditingMode() {
        //check if the table has been reordered, if so make the changes persistent
        if self.tableView.isEditing && bookmarksOrderChanged {
            orderedBookmarkGUIDs = orderUpdatedBookmarkGUIDs
            postAsyncToBackground {
                if let sqllitbk = self.profile.bookmarks as? MergedSQLiteBookmarks {
                    let folderGUID = self.bookmarkFolder?.guid ?? BookmarkRoots.MobileFolderGUID
                    
                    sqllitbk.reorderBookmarks(folderGUID, bookmarksOrder: self.orderedBookmarkGUIDs) {
                        postAsyncToMain {
                            //reorder ok
                            //TODO add toast popup with message for success
                        }
                    }
                }
            }
            
        }
        
        DispatchQueue.main.async {
            self.tableView.setEditing(!self.tableView.isEditing, animated: true)
            self.updateAddRemoveFolderButton()
            self.editBookmarksButton.title = self.tableView.isEditing ? NSLocalizedString("Done", comment: "Done") : NSLocalizedString("Edit", comment: "Edit")
            self.editBookmarksButton.style = self.tableView.isEditing ? .done : .plain
        }
    }
    
    /*
     * Subfolders can only be added to the root folder, and only subfolders can be deleted/removed, so we use
     * this button (on the left side of the bookmarks toolbar) for both functions depending on where we are.
     * Therefore when we enter edit mode on the root we show 'new folder' 
     * the button disappears when not in edit mode in both cases. When a subfolder is not empty,
     * pressing the remove folder button will show an error message explaining why (suboptimal, but allows to expose this functionality)
     */
    func updateAddRemoveFolderButton() {
        
        if !tableView.isEditing {
            addRemoveFolderButton.isEnabled = false
            addRemoveFolderButton.title = nil
            return
        }

        addRemoveFolderButton.isEnabled = true

        var targetButton:UIBarButtonItem!
        
        if bookmarkFolder == nil { //on root, this button allows adding subfolders
            targetButton = addFolderButton
        } else { //on a subfolder, this button allows removing the current folder (if empty)
            targetButton = removeFolderButton
        }
        
        addRemoveFolderButton.title = targetButton.title
        addRemoveFolderButton.style = targetButton.style
        addRemoveFolderButton.target = targetButton.target
        addRemoveFolderButton.action = targetButton.action
    }
    
    func createEditBookmarksToolbar() {
        var items = [UIBarButtonItem]()
        
        items.append(UIBarButtonItem.createFixedSpaceItem(5))

        //these two buttons are created as placeholders for the data/actions in each case. see #updateAddRemoveFolderButton and 
        //#switchTableEditingMode
        addFolderButton = UIBarButtonItem(title: NSLocalizedString("New Folder", comment: "New Folder"),
                                          style: .plain, target: self, action: #selector(onAddBookmarksFolderButton))
        removeFolderButton = UIBarButtonItem(title: NSLocalizedString("Delete Folder", comment: "Delete Folder"),
                                             style: .plain, target: self, action: #selector(onDeleteBookmarksFolderButton))
        
        //this is the button that actually lives in the toolbar
        addRemoveFolderButton = UIBarButtonItem()
        items.append(addRemoveFolderButton)

        updateAddRemoveFolderButton()
        
        items.append(UIBarButtonItem(barButtonSystemItem: .flexibleSpace, target: self, action: nil))


        editBookmarksButton = UIBarButtonItem(title: NSLocalizedString("Edit", comment: "Edit"),
                                              style: .plain, target: self, action: #selector(onEditBookmarksButton))
        items.append(editBookmarksButton)
        items.append(UIBarButtonItem.createFixedSpaceItem(5))
        
        
        editBookmarksToolbar.items = items
    }
    
    func onDeleteBookmarksFolderButton() {
        guard let currentFolder = self.bookmarkFolder else {
            NSLog("Delete folder button pressed but no folder object exists (probably at root), ignoring.")
            return
        }
        let itemCount = source?.current.count ?? 0
        let folderGUID = currentFolder.guid
        let canDeleteFolder = (itemCount == 0)
        let title = canDeleteFolder ? "Delete Folder" : "Oops!"
        let message = canDeleteFolder ? "Deleting folder \"\(currentFolder.title)\". This action can't be undone. Are you sure?" : "You can't delete a folder that contains items. Please delete all items and try again."
        let okButtonTitle = canDeleteFolder ? "Delete" : "OK"
        let okButtonType = canDeleteFolder ? UIAlertActionStyle.Destructive : UIAlertActionStyle.Default
        
        let alert = UIAlertController(title: title, message: message, preferredStyle: UIAlertControllerStyle.Alert)
        alert.addAction(UIAlertAction(title: okButtonTitle, style: okButtonType,
                                        handler: { (alertA: UIAlertAction!) in
                                            if canDeleteFolder {
                                                
                                                self.profile.bookmarks.modelFactory >>== {
                                                    $0.removeByGUID(folderGUID).uponQueue(dispatch_get_main_queue()) { res in
                                                        if res.isSuccess {
                                                            self.navigationController?.popViewControllerAnimated(true)
                                                            self.currentBookmarksPanel().reloadData()
                                                        }
                                                    }
                                                }

                                                
                                            }
                                        }))
        if canDeleteFolder {
            alert.addAction(UIAlertAction(title: "Cancel", style: UIAlertActionStyle.Cancel,
                handler: nil))
            }
            self.presentViewController(alert, animated: true) {
        }
    }
    
    func onAddBookmarksFolderButton() {
        
        let alert = UIAlertController(title: "New Folder", message: "Enter folder name", preferredStyle: UIAlertControllerStyle.alert)

        let okAction = UIAlertAction(title: "OK", style: UIAlertActionStyle.default) { (alertA: UIAlertAction!) in
                                                                                            self.addFolder(alertA, alertController:alert)
                                                                                        }
        let cancelAction = UIAlertAction(title: "Cancel", style: UIAlertActionStyle.cancel, handler: nil)
        
        alert.addAction(okAction)
        alert.addAction(cancelAction)
    
        alert.addTextField(configurationHandler: {(textField: UITextField!) in
                    textField.placeholder = "<folder name>"
                    textField.isSecureTextEntry = false
                })
        
        self.present(alert, animated: true) {}
    }

    func addFolder(_ alert: UIAlertAction!, alertController: UIAlertController) {
        postAsyncToBackground {
            if let folderName = alertController.textFields![0].text  {
                if let sqllitbk = self.profile.bookmarks as? MergedSQLiteBookmarks {
                    sqllitbk.createFolder(folderName) {
                        postAsyncToMain {
                            self.reloadData()
                        }
                    }
                }
            }
        }
    }
    
    func onEditBookmarksButton() {
        switchTableEditingMode()
    }

    func tableView(_ tableView: UITableView, moveRowAtIndexPath sourceIndexPath: IndexPath, toIndexPath destinationIndexPath: IndexPath) {
        let item = orderUpdatedBookmarkGUIDs.remove(at: (sourceIndexPath as NSIndexPath).item)
        orderUpdatedBookmarkGUIDs.insert(item, at: (destinationIndexPath as NSIndexPath).item)
    }
    
    func tableView(_ tableView: UITableView, canMoveRowAtIndexPath indexPath: IndexPath) -> Bool {
        return true
    }
    
    func notificationReceived(_ notification: Notification) {
        switch notification.name {
        case NotificationFirefoxAccountChanged:
            self.reloadData()
            break
        default:
            // no need to do anything at all
            log.warning("Received unexpected notification \(notification.name)")
            break
        }
    }

    fileprivate func onModelFetched(_ result: Maybe<BookmarksModel>) {
        guard let model = result.successValue else {
            self.onModelFailure(result.failureValue)
            return
        }
        self.onNewModel(model)
    }

    fileprivate func onNewModel(_ model: BookmarksModel) {
        postAsyncToMain {
            let count = self.currentItemCount
            self.source = model
            let newCount = self.currentItemCount
            
            if self.bookmarkFolder == nil { //we're on root, load folders into picker
                self.folderPicker = BookmarkFoldersPickerDataSource()
            }
            self.orderedBookmarkGUIDs.removeAll()
            


            let rootFolder = MemoryBookmarkFolder(guid: BookmarkRoots.MobileFolderGUID, title: "Root Folder", children: [])
            self.folderPicker.addFolder(rootFolder)
            for i in 0..<newCount {
                if let item = self.source!.current[i] {
                    self.orderedBookmarkGUIDs.append(item.guid)
                    if let f = item as? BookmarkFolder {
                        self.folderPicker.addFolder(f)
                    }
                }
            }
            self.orderUpdatedBookmarkGUIDs = self.orderedBookmarkGUIDs
            
            self.tableView.reloadData()
            if count != newCount && newCount > 0 {
                let newIndexPath = IndexPath(row: newCount-1, section: 0)
                self.currentBookmarksPanel().tableView.scrollToRow(at: newIndexPath, at: UITableViewScrollPosition.middle, animated: true)
            }
        }
    }

    fileprivate func onModelFailure(_ e: Any) {
        editBookmarksButton.isEnabled = false
        log.error("Error: failed to get data: \(e)")
    }
    
    func currentBookmarksPanel() -> BookmarksPanel {
        return self.navigationController?.visibleViewController as! BookmarksPanel
    }
    
    override func reloadData() {
        if let source = self.source {
            source.reloadData().upon(self.onModelFetched)
        }
    }

    override func tableView(_ tableView: UITableView, numberOfRowsInSection section: Int) -> Int {
        return source?.current.count ?? 0
    }

    override func tableView(_ tableView: UITableView, cellForRowAt indexPath: IndexPath) -> UITableViewCell {
        guard let source = source, let bookmark = source.current[indexPath.row] else { return super.tableView(tableView, cellForRowAt: indexPath) }
        switch (bookmark) {
        case let item as BookmarkItem:
            let cell = super.tableView(tableView, cellForRowAt: indexPath)
            cell.textLabel?.font = UIFont.systemFont(ofSize: 14)
            if item.title.isEmpty {
                cell.textLabel?.text = item.url
            } else {
                cell.textLabel?.text = item.title
            }
            if let url = bookmark.favicon?.url.asURL , url.scheme == "asset" {
                cell.imageView?.image = UIImage(named: url.host!)
            } else {
                cell.imageView?.setIcon(bookmark.favicon, withPlaceholder: FaviconFetcher.defaultFavicon)
            }
            cell.accessoryType = .none

            return cell
        case is BookmarkSeparator:
            return tableView.dequeueReusableCell(withIdentifier: BookmarkSeparatorCellIdentifier, for: indexPath)
        case let bookmark as BookmarkFolder:
            let cell = super.tableView(tableView, cellForRowAt: indexPath)
            cell.textLabel?.font = UIFont.boldSystemFont(ofSize: 14)
            cell.textLabel?.text = bookmark.title
            cell.imageView?.image = UIImage(named: "bookmarks_folder_hollow")

            cell.accessoryType = .disclosureIndicator

            return cell
        default:
            // This should never happen.
            return super.tableView(tableView, cellForRowAt: indexPath)
        }
    }

    func tableView(_ tableView: UITableView, willDisplayCell cell: UITableViewCell, forRowAtIndexPath indexPath: IndexPath) {
        if let cell = cell as? BookmarkFolderTableViewCell {
            cell.textLabel?.font = DynamicFontHelper.defaultHelper.DeviceFontHistoryPanel
        }
    }

    override func tableView(_ tableView: UITableView, viewForHeaderInSection section: Int) -> UIView? {
        return nil
    }

    override func tableView(_ tableView: UITableView, heightForRowAt indexPath: IndexPath) -> CGFloat {
        if let it = self.source?.current[indexPath.row] , it is BookmarkSeparator {
            return BookmarksPanelUX.SeparatorRowHeight
        }

        return super.tableView(tableView, heightForRowAt: indexPath)
    }

    override func tableView(_ tableView: UITableView, heightForHeaderInSection section: Int) -> CGFloat {
        return 0
    }

    override func tableView(_ tableView: UITableView, hasFullWidthSeparatorForRowAtIndexPath indexPath: IndexPath) -> Bool {
        // Show a full-width border for cells above separators, so they don't have a weird step.
        // Separators themselves already have a full-width border, but let's force the issue
        // just in case.
        let this = self.source?.current[indexPath.row]
        if ((indexPath as NSIndexPath).row + 1) < self.source?.current.count {
            let below = self.source?.current[indexPath.row + 1]
            if this is BookmarkSeparator || below is BookmarkSeparator {
                return true
            }
        }
        return super.tableView(tableView, hasFullWidthSeparatorForRowAtIndexPath: indexPath)
    }
    
    func tableView(_ tableView: UITableView, didSelectRowAtIndexPath indexPath: IndexPath) {
        tableView.deselectRow(at: indexPath, animated: false)
        guard let source = source else {
            return
        }

        let bookmark = source.current[indexPath.row]

        switch (bookmark) {
        case let item as BookmarkItem:
            if let url = URL(string: item.url) {
                homePanelDelegate?.homePanel(self, didSelectURL: url, visitType: VisitType.Bookmark)
            }
            break

        case let folder as BookmarkFolder:
            log.debug("Selected \(folder.guid)")
            let nextController = BookmarksPanel()
            nextController.parentFolders = parentFolders + [source.current]
            nextController.bookmarkFolder = folder
            nextController.folderPicker = self.folderPicker
            nextController.homePanelDelegate = self.homePanelDelegate
            nextController.profile = self.profile
            source.modelFactory.uponQueue(DispatchQueue.main) { maybe in
                guard let factory = maybe.successValue else {
                    // Nothing we can do.
                    return
                }
                nextController.source = BookmarksModel(modelFactory: factory, root: folder)
                //on subfolders, the folderpicker is the same as the root
                self.navigationController?.pushViewController(nextController, animated: true)
            }
            break

        default:
            // You can't do anything with separators.
            break
        }
    }

    func tableView(_ tableView: UITableView, commitEditingStyle editingStyle: UITableViewCellEditingStyle, forRowAtIndexPath indexPath: IndexPath) {
        // Intentionally blank. Required to use UITableViewRowActions
    }

    func tableView(_ tableView: UITableView, editingStyleForRowAtIndexPath indexPath: IndexPath) -> UITableViewCellEditingStyle {
        guard let source = source else {
            return .none
        }

        if source.current[indexPath.row] is BookmarkSeparator {
            // Because the deletion block is too big.
            return .none
        }

        if source.current.itemIsEditableAtIndex(indexPath.row) ?? false {
            return .delete
        }

        return .none
    }
    
    func tableView(_ tableView: UITableView, editActionsForRowAtIndexPath indexPath: IndexPath) -> [AnyObject]? {
        guard let source = self.source else {
            return [AnyObject]()
        }

        let deleteTitle = NSLocalizedString("Delete", tableName: "BookmarksPanel", comment: "Action button for deleting bookmarks in the bookmarks panel.")
        let editTitle = NSLocalizedString("Edit", tableName: "BookmarksPanel", comment: "Action button for editing bookmarks in the bookmarks panel.")

        let delete = UITableViewRowAction(style: UITableViewRowActionStyle(), title: deleteTitle, handler: { (action, indexPath) in
            guard let bookmark = source.current[indexPath.row] else {
                return
            }

            assert(!(bookmark is BookmarkFolder))
            //folder deletion is dealt with within a folder.
            if bookmark is BookmarkFolder {
                // TODO: check whether the folder is empty (excluding separators). If it isn't
                // then we must ask the user to confirm. Bug 1232810.
                log.debug("Not deleting folder.")
                return
            }

            log.debug("Removing rows \(indexPath).")

            // Block to do this -- this is UI code.
            guard let factory = source.modelFactory.value.successValue else {
                log.error("Couldn't get model factory. This is unexpected.")
                self.onModelFailure(DatabaseError(description: "Unable to get factory."))
                return
            }

            if let err = factory.removeByGUID(bookmark.guid).value.failureValue {
                log.debug("Failed to remove \(bookmark.guid).")
                self.onModelFailure(err)
                return
            }

            guard let reloaded = source.reloadData().value.successValue else {
                log.debug("Failed to reload model.")
                return
            }

            self.tableView.beginUpdates()
            self.source = reloaded
            self.tableView.deleteRows(at: [indexPath], with: UITableViewRowAnimation.left)
            self.tableView.endUpdates()

            NotificationCenter.defaultCenter().postNotificationName(BookmarkStatusChangedNotification, object: bookmark, userInfo:["added": false])
        })
        
        
        let rename = UITableViewRowAction(style: UITableViewRowActionStyle.normal, title: editTitle, handler: { (action, indexPath) in
            guard let bookmark = source.current[indexPath.row] else {
                return
            }
            
            if bookmark is BookmarkFolder {
                return
            }
            let currentFolderGUID = self.bookmarkFolder?.guid ?? BookmarkRoots.MobileFolderGUID
            let cell = self.tableView(self.tableView, cellForRowAt: indexPath)
            let vc: BookmarkEditViewController = BookmarkEditViewController(sourceTable:self.tableView, sourceCell: cell, indexPath: indexPath, currentFolderGUID:currentFolderGUID, bookmarksPanel: self, bookmark: bookmark as! BookmarkItem, folderPickerDataSource: self.folderPicker)
            self.modalPresentationStyle = .currentContext
           
            postAsyncToMain {
                self.present(vc, animated: true) {}
            }
        })

        return [delete, rename]
    }

    
    func editBookmark(_ bookmark:BookmarkNode, newTitle:String?, newFolderGUID: String?, atIndexPath indexPath: IndexPath) {
        postAsyncToBackground {
            if let sqllitbk = self.profile.bookmarks as? MergedSQLiteBookmarks {
                if newFolderGUID == nil { //rename only
                    sqllitbk.editBookmark(bookmark, newTitle:newTitle) {
                        postAsyncToMain {
                            //no need to reload everything, just change the title on the object and
                            self.tableView.beginUpdates()
                            bookmark.title = newTitle!
                            self.tableView.reloadRowsAtIndexPaths([indexPath], withRowAnimation: UITableViewRowAnimation.Fade)
                            self.tableView.endUpdates()

                            self.reloadData()
                        }
                    }
                }
                else {
                    //move and reload
                    sqllitbk.editBookmark(bookmark, newTitle:newTitle, newParentID: newFolderGUID) {
                        postAsyncToMain {
                            self.reloadData()
                        }
                    }

                }
            }
        }
    }
}

private protocol BookmarkFolderTableViewHeaderDelegate {
    func didSelectHeader()
}

extension BookmarksPanel: BookmarkFolderTableViewHeaderDelegate {
    fileprivate func didSelectHeader() {
        self.navigationController?.popViewController(animated: true)
    }
}

class BookmarkFolderTableViewCell: TwoLineTableViewCell {
    fileprivate let ImageMargin: CGFloat = 12

    override init(style: UITableViewCellStyle, reuseIdentifier: String?) {
        super.init(style: style, reuseIdentifier: reuseIdentifier)
        textLabel?.backgroundColor = UIColor.clear
        textLabel?.tintColor = BookmarksPanelUX.BookmarkFolderTextColor

        imageView?.image = UIImage(named: "bookmarkFolder")

        self.editingAccessoryType = .disclosureIndicator

        separatorInset = UIEdgeInsets.zero
    }

    required init?(coder aDecoder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }
}

private class BookmarkFolderTableViewHeader : UITableViewHeaderFooterView {
    var delegate: BookmarkFolderTableViewHeaderDelegate?

    lazy var titleLabel: UILabel = {
        let label = UILabel()
        label.textColor = UIConstants.HighlightBlue
        return label
    }()

    lazy var chevron: ChevronView = {
        let chevron = ChevronView(direction: .left)
        chevron.tintColor = UIConstants.HighlightBlue
        chevron.lineWidth = BookmarksPanelUX.BookmarkFolderChevronLineWidth
        return chevron
    }()

    lazy var topBorder: UIView = {
        let view = UIView()
        view.backgroundColor = SiteTableViewControllerUX.HeaderBorderColor
        return view
    }()

    lazy var bottomBorder: UIView = {
        let view = UIView()
        view.backgroundColor = SiteTableViewControllerUX.HeaderBorderColor
        return view
    }()

    override var textLabel: UILabel? {
        return titleLabel
    }

    override init(reuseIdentifier: String?) {
        super.init(reuseIdentifier: reuseIdentifier)

        isUserInteractionEnabled = true

        let tapGestureRecognizer = UITapGestureRecognizer(target: self, action: #selector(BookmarkFolderTableViewHeader.viewWasTapped(_:)))
        tapGestureRecognizer.numberOfTapsRequired = 1
        addGestureRecognizer(tapGestureRecognizer)

        addSubview(topBorder)
        addSubview(bottomBorder)
        contentView.addSubview(chevron)
        contentView.addSubview(titleLabel)

        chevron.snp_makeConstraints { make in
            make.left.equalTo(contentView).offset(BookmarksPanelUX.BookmarkFolderHeaderViewChevronInset)
            make.centerY.equalTo(contentView)
            make.size.equalTo(BookmarksPanelUX.BookmarkFolderChevronSize)
        }

        titleLabel.snp_makeConstraints { make in
            make.left.equalTo(chevron.snp_right).offset(BookmarksPanelUX.BookmarkFolderHeaderViewChevronInset)
            make.right.greaterThanOrEqualTo(contentView).offset(-BookmarksPanelUX.BookmarkFolderHeaderViewChevronInset)
            make.centerY.equalTo(contentView)
        }

        topBorder.snp_makeConstraints { make in
            make.left.right.equalTo(self)
            make.top.equalTo(self).offset(-0.5)
            make.height.equalTo(0.5)
        }

        bottomBorder.snp_makeConstraints { make in
            make.left.right.bottom.equalTo(self)
            make.height.equalTo(0.5)
        }
    }

    required init?(coder aDecoder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    @objc fileprivate func viewWasTapped(_ gestureRecognizer: UITapGestureRecognizer) {
        delegate?.didSelectHeader()
    }
}
