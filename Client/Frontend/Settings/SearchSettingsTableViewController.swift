/* This Source Code Form is subject to the terms of the Mozilla Public
 * License, v. 2.0. If a copy of the MPL was not distributed with this
 * file, You can obtain one at http://mozilla.org/MPL/2.0/. */

import UIKit

class SearchSettingsTableViewController: UITableViewController {
    fileprivate let SectionDefault = 0
    fileprivate let ItemDefaultEngine = 0
    fileprivate let ItemDefaultSuggestions = 1
    fileprivate let NumberOfItemsInSectionDefault = 2
    fileprivate let SectionOrder = 1
    fileprivate let NumberOfSections = 2
    fileprivate let IconSize = CGSize(width: OpenSearchEngine.PreferredIconSize, height: OpenSearchEngine.PreferredIconSize)
    fileprivate let SectionHeaderIdentifier = "SectionHeaderIdentifier"

    var model: SearchEngines!

    override func viewDidLoad() {
        super.viewDidLoad()

        navigationItem.title = NSLocalizedString("Search", comment: "Navigation title for search settings.")

        // To allow re-ordering the list of search engines at all times.
        tableView.isEditing = true
        // So that we push the default search engine controller on selection.
        tableView.allowsSelectionDuringEditing = true

        tableView.register(SettingsTableSectionHeaderFooterView.self, forHeaderFooterViewReuseIdentifier: SectionHeaderIdentifier)

        // Insert Done button if being presented outside of the Settings Nav stack
        if !(self.navigationController is SettingsNavigationController) {
            self.navigationItem.leftBarButtonItem = UIBarButtonItem(title: NSLocalizedString("Done", comment: "Done button label for search settings table"), style: .done, target: self, action: #selector(SearchSettingsTableViewController.SELDismiss))
        }

        let footer = SettingsTableSectionHeaderFooterView(frame: CGRect(x: 0, y: 0, width: tableView.bounds.width, height: 44))
        footer.showBottomBorder = false
        tableView.tableFooterView = footer

        tableView.separatorColor = UIConstants.TableViewSeparatorColor
        tableView.backgroundColor = UIConstants.TableViewHeaderBackgroundColor
    }

    override func tableView(_ tableView: UITableView, cellForRowAt indexPath: IndexPath) -> UITableViewCell {
        var cell: UITableViewCell!
        var engine: OpenSearchEngine!

        if (indexPath as NSIndexPath).section == SectionDefault {
            switch (indexPath as NSIndexPath).item {
            case ItemDefaultEngine:
                engine = model.defaultEngine
                cell = UITableViewCell(style: UITableViewCellStyle.default, reuseIdentifier: nil)
                cell.editingAccessoryType = UITableViewCellAccessoryType.disclosureIndicator
                cell.accessibilityLabel = NSLocalizedString("Default Search Engine", comment: "Accessibility label for default search engine setting.")
                cell.accessibilityValue = engine.shortName
                cell.textLabel?.text = engine.shortName
                cell.imageView?.image = engine.image?.createScaled(IconSize)

            case ItemDefaultSuggestions:
                cell = UITableViewCell(style: UITableViewCellStyle.default, reuseIdentifier: nil)
                cell.textLabel?.text = NSLocalizedString("Show Search Suggestions", comment: "Label for show search suggestions setting.")
                let toggle = UISwitch()
                toggle.onTintColor = UIConstants.ControlTintColor
                toggle.addTarget(self, action: #selector(SearchSettingsTableViewController.SELdidToggleSearchSuggestions(_:)), for: UIControlEvents.valueChanged)
                toggle.isOn = model.shouldShowSearchSuggestions
                cell.editingAccessoryView = toggle
                cell.selectionStyle = .none

            default:
                // Should not happen.
                break
            }
        } else {
            // The default engine is not a quick search engine.
            let index = (indexPath as NSIndexPath).item + 1
            engine = model.orderedEngines[index]

            cell = UITableViewCell(style: UITableViewCellStyle.default, reuseIdentifier: nil)
            cell.showsReorderControl = true

            let toggle = UISwitch()
            toggle.onTintColor = UIConstants.ControlTintColor
            // This is an easy way to get from the toggle control to the corresponding index.
            toggle.tag = index
            toggle.addTarget(self, action: #selector(SearchSettingsTableViewController.SELdidToggleEngine(_:)), for: UIControlEvents.valueChanged)
            toggle.isOn = model.isEngineEnabled(engine)

            cell.editingAccessoryView = toggle

            cell.textLabel?.text = engine.shortName
            cell.imageView?.image = engine.image?.createScaled(IconSize)

            cell.selectionStyle = .none
        }

        // So that the seperator line goes all the way to the left edge.
        cell.separatorInset = UIEdgeInsets.zero

        return cell
    }

    override func numberOfSections(in tableView: UITableView) -> Int {
        return NumberOfSections
    }

    override func tableView(_ tableView: UITableView, numberOfRowsInSection section: Int) -> Int {
        if section == SectionDefault {
            return NumberOfItemsInSectionDefault
        } else {
            // The first engine -- the default engine -- is not shown in the quick search engine list.
            return model.orderedEngines.count - 1
        }
    }

    override func tableView(_ tableView: UITableView, willSelectRowAt indexPath: IndexPath) -> IndexPath? {
        if (indexPath as NSIndexPath).section == SectionDefault && (indexPath as NSIndexPath).item == ItemDefaultEngine {
            let searchEnginePicker = SearchEnginePicker()
            // Order alphabetically, so that picker is always consistently ordered.
            // Every engine is a valid choice for the default engine, even the current default engine.
            searchEnginePicker.engines = model.orderedEngines.sorted { e, f in e.shortName < f.shortName }
            searchEnginePicker.delegate = self
            searchEnginePicker.selectedSearchEngineName = model.defaultEngine.shortName
            navigationController?.pushViewController(searchEnginePicker, animated: true)
        }
        return nil
    }

    // Don't show delete button on the left.
    override func tableView(_ tableView: UITableView, editingStyleForRowAt indexPath: IndexPath) -> UITableViewCellEditingStyle {
        return UITableViewCellEditingStyle.none
    }

    // Don't reserve space for the delete button on the left.
    override func tableView(_ tableView: UITableView, shouldIndentWhileEditingRowAt indexPath: IndexPath) -> Bool {
        return false
    }

    // Hide a thin vertical line that iOS renders between the accessoryView and the reordering control.
    override func tableView(_ tableView: UITableView, willDisplay cell: UITableViewCell, forRowAt indexPath: IndexPath) {
        if cell.isEditing {
            for v in cell.subviews {
                if v.frame.width == 1.0 {
                    v.backgroundColor = UIColor.clear
                }
            }
        }
    }

    override func tableView(_ tableView: UITableView, heightForHeaderInSection section: Int) -> CGFloat {
        return 44
    }

    override func tableView(_ tableView: UITableView, viewForHeaderInSection section: Int) -> UIView? {
        let headerView = tableView.dequeueReusableHeaderFooterView(withIdentifier: SectionHeaderIdentifier) as! SettingsTableSectionHeaderFooterView
        var sectionTitle: String
        if section == SectionDefault {
            sectionTitle = NSLocalizedString("Default Search Engine", comment: "Title for default search engine settings section.")
        } else {
            sectionTitle = NSLocalizedString("Quick-search Engines", comment: "Title for quick-search engines settings section.")
        }
        headerView.titleLabel.text = sectionTitle

        return headerView
    }

    override func tableView(_ tableView: UITableView, canMoveRowAt indexPath: IndexPath) -> Bool {
        if (indexPath as NSIndexPath).section == SectionDefault {
            return false
        } else {
            return true
        }
    }

    override func tableView(_ tableView: UITableView, moveRowAt indexPath: IndexPath, to newIndexPath: IndexPath) {
        // The first engine (default engine) is not shown in the list, so the indices are off-by-1.
        let index = (indexPath as NSIndexPath).item + 1
        let newIndex = (newIndexPath as NSIndexPath).item + 1
        let engine = model.orderedEngines.remove(at: index)
        model.orderedEngines.insert(engine, at: newIndex)
        tableView.reloadData()
    }

    // Snap to first or last row of the list of engines.
    override func tableView(_ tableView: UITableView, targetIndexPathForMoveFromRowAt sourceIndexPath: IndexPath, toProposedIndexPath proposedDestinationIndexPath: IndexPath) -> IndexPath {
        // You can't drag or drop on the default engine.
        if (sourceIndexPath as NSIndexPath).section == SectionDefault || (proposedDestinationIndexPath as NSIndexPath).section == SectionDefault {
            return sourceIndexPath
        }

        if ((sourceIndexPath as NSIndexPath).section != (proposedDestinationIndexPath as NSIndexPath).section) {
            var row = 0
            if ((sourceIndexPath as NSIndexPath).section < (proposedDestinationIndexPath as NSIndexPath).section) {
                row = tableView.numberOfRows(inSection: (sourceIndexPath as NSIndexPath).section) - 1
            }
            return IndexPath(row: row, section: (sourceIndexPath as NSIndexPath).section)
        }

        return proposedDestinationIndexPath
    }

    func SELdidToggleEngine(_ toggle: UISwitch) {
        let engine = model.orderedEngines[toggle.tag] // The tag is 1-based.
        if toggle.isOn {
            model.enableEngine(engine)
        } else {
            model.disableEngine(engine)
        }
    }

    func SELdidToggleSearchSuggestions(_ toggle: UISwitch) {
        // Setting the value in settings dismisses any opt-in.
        model.shouldShowSearchSuggestionsOptIn = false
        model.shouldShowSearchSuggestions = toggle.isOn
    }

    func SELcancel() {
        navigationController?.popViewController(animated: true)
    }

    func SELDismiss() {
        self.dismiss(animated: true, completion: nil)
    }
}

extension SearchSettingsTableViewController: SearchEnginePickerDelegate {
    func searchEnginePicker(_ searchEnginePicker: SearchEnginePicker, didSelectSearchEngine searchEngine: OpenSearchEngine?) {
        if let engine = searchEngine {
            model.defaultEngine = engine
            self.tableView.reloadData()
        }
        navigationController?.popViewController(animated: true)
    }
}
