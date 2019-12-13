//
//  MLCardFormViewController.swift
//  MLCardForm
//
//  Created by Esteban Adrian Boffa on 30/10/2019.
//

import UIKit
import MLCardDrawer
import MLUI

open class MLCardFormViewController: MLCardFormBaseViewController {
    // MARK: Outlets.
    @IBOutlet weak var cardContainerView: UIView!
    @IBOutlet weak var progressBarView: UIProgressView!
    @IBOutlet weak var spinnerContainerView: UIView!
    @IBOutlet weak var spinnerView: MLSpinner!
    
    // Constraints.
    @IBOutlet weak var containerBottomConstraint: NSLayoutConstraint!

    // MARK: Private Vars
    private weak var lifeCycleDelegate: MLCardFormLifeCycleDelegate?
    private var cardDrawer: MLCardDrawerController?
    private weak var cardFieldCollectionView: UICollectionView?
    
    private let cardFieldCellInset: CGFloat = 30
    private let cardFieldHeight: CGFloat = 75

    // MARK: IssuersScreen vars
    private var issuersVC: MLCardFormIssuersViewController?
    private var setupControllerCompleted = false

    let viewModel: MLCardFormViewModel = MLCardFormViewModel()

    override open func viewDidAppear(_ animated: Bool) {
        super.viewDidAppear(animated)
        if !setupControllerCompleted {
            setupProgress()
            setupCardDrawer()
            setupFieldCollectionView()
            showViewWithAnimation()
            setupTempTextField()
            setupSpinner()
            viewModel.viewModelDelegate = self
            setupControllerCompleted = true
        }
    }

    open override func viewDidLoad() {
        super.viewDidLoad()
        title = AppBar.Generic.title
        let (backgroundNavigationColor, textNavigationColor) = viewModel.getNavigationBarCustomColor()
        super.loadStyles(customNavigationBackgroundColor: backgroundNavigationColor, customNavigationTextColor: textNavigationColor)
        addStatusBarBackground(color: backgroundNavigationColor)
        setupCardContainer()
    }

    override open func viewWillAppear(_ animated: Bool) {
        super.viewWillAppear(animated)
        setupKeyboardNotifications()
    }

    override open func viewWillDisappear(_ animated: Bool) {
        super.viewWillDisappear(animated)
        removeKeyboardNotifications()
    }
}

// MARK: Public API.
extension MLCardFormViewController {
    public static func setupWithBuilder(_ builder: MLCardFormBuilder) -> MLCardFormViewController {
        let controller = MLCardFormViewController(nibName: "MLCardFormViewController", bundle: Bundle(for: MLCardFormViewController.self))
        controller.lifeCycleDelegate = builder.lifeCycleDelegate
        controller.viewModel.updateWithBuilder(builder)
        return controller
    }
}

// MARK: AppBar
extension MLCardFormViewController {
    enum AppBar: String {
        case Generic
        case CreditCard = "credit_card"
        case DebitCard = "debit_card"

        var title: String {
            switch self {
            case .Generic:
                return "Nueva tarjeta".localized
            case .CreditCard:
                return "Nueva tarjeta de crédito".localized
            case .DebitCard:
                return "Nueva tarjeta de débito".localized
            }
        }
    }
}

// MARK:  Privates.
private extension MLCardFormViewController {
    func getCardData(binNumber: String, showProggressAndSnackBar: Bool = false) {
        if showProggressAndSnackBar {
            showProgress()
        }
        viewModel.getCardData(binNumber: binNumber, completion: { (result: Result<String, Error>) in
            if showProggressAndSnackBar {
                DispatchQueue.main.async { [weak self] in
                    guard let self = self else { return }
                    self.hideProgress(completion: { _ in
                        switch result {
                        case .success:
                            break
                        case .failure:
                            // Show error to the user
                            MLSnackbar.show(withTitle: "Algo salió mal.".localized, type: MLSnackbarType.error(), duration: MLSnackbarDuration.long)
                        }
                    })
                }
            }
        })
    }
    
    func addCard() {
        showProgress()
        viewModel.addCard(completion: { (result: Result<String, Error>) in
            DispatchQueue.main.async { [weak self] in
                guard let self = self else { return }
                self.hideProgress()
                switch result {
                case .success(let cardID):
                    // Notify listener
                    self.lifeCycleDelegate?.didAddCard(cardID: cardID)
                    // Save data for next time
                    self.viewModel.saveDataForReuse()
                case .failure:
                    // Notify listener
                    self.lifeCycleDelegate?.didFailAddCard()
                    // Show error to the user
                    MLSnackbar.show(withTitle: "Algo salió mal.".localized, actionTitle: "Reintentar".localized, actionBlock: { [weak self] in
                        self?.addCard()
                    }, type: MLSnackbarType.error(), duration: MLSnackbarDuration.indefinitely)
                }
            }
        })
    }
    
    func setupProgress() {
        progressBarView.progressTintColor = MLStyleSheetManager.styleSheet.secondaryColor
        progressBarView.setProgress(0, animated: true)
    }
    
    func setupCardDrawer() {
        cardDrawer = MLCardDrawerController(viewModel.cardUIHandler, viewModel.cardDataHandler)
        cardDrawer?.view.backgroundColor = .clear
        cardDrawer?.setUp(inView: cardContainerView)
        cardContainerView.addShadow()
    }

    func setupCardContainer() {
        cardContainerView.backgroundColor = .clear
        containerBottomConstraint.constant = containerBottomConstraint.constant - UIScreen.main.bounds.height
    }
    
    func setupFieldCollectionView() {
        viewModel.setupDefaultCardFormFields(notifierProtocol: self)
        
        let layout = UICollectionViewFlowLayout()
        layout.scrollDirection = .horizontal
        layout.minimumLineSpacing = 0
        layout.minimumInteritemSpacing = 10
        layout.sectionInset = UIEdgeInsets(top: 0, left: cardFieldCellInset, bottom: 0, right: cardFieldCellInset)
        
        let collectionView = UICollectionView(frame: .zero, collectionViewLayout: layout)
        collectionView.isScrollEnabled = false
        collectionView.translatesAutoresizingMaskIntoConstraints = false
        collectionView.register(MLCardFormFieldCell.self, forCellWithReuseIdentifier: MLCardFormFieldCell.cellIdentifier)
        collectionView.showsHorizontalScrollIndicator = false
        collectionView.showsVerticalScrollIndicator = false
        collectionView.alpha = 0

        view.addSubview(collectionView)
        collectionView.backgroundColor = .white
        collectionView.delegate = self
        collectionView.dataSource = self
        
        NSLayoutConstraint.activate([
            collectionView.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            collectionView.trailingAnchor.constraint(equalTo: view.trailingAnchor),
            collectionView.topAnchor.constraint(equalTo: cardContainerView.bottomAnchor, constant: viewModel.isSmallDevice() ? 8 : 24),
            collectionView.heightAnchor.constraint(equalToConstant: cardFieldHeight),
        ])
        
        cardFieldCollectionView = collectionView
    }

    func setupIssuersScreen() {
        issuersVC = MLCardFormIssuersViewController(viewModel: self.viewModel)
        if let issuersVC = issuersVC {
            issuersVC.delegate = self
            let issuersNavigation: UINavigationController = UINavigationController(rootViewController: issuersVC)
            navigationController?.present(issuersNavigation, animated: true, completion: nil)
        }
    }

    private func showViewWithAnimation() {
        if let field = viewModel.cardFormFields?.first?.first {
            field.doFocus()
            if viewModel.updateProgressWithCompletion {
                updateProgressFromField(field)
            }
        }

        UIView.animate(withDuration: 0.3, animations: { [weak self] in
            self?.cardFieldCollectionView?.alpha = 1
            self?.cardContainerView.alpha = 1
        })
    }

    private func updateProgressFromField(_ cardFormField: MLCardFormField) {
        progressBarView.setProgress(viewModel.getProgressFromField(cardFormField), animated: true)
    }

    private func setupTempTextField() {
        viewModel.tempTextField.notifierProtocol = self
        view.addSubview(viewModel.tempTextField)
    }
    
    private func setupSpinner() {
        let color = MLStyleSheetManager.styleSheet.primaryColor
        let spinnerConfig = MLSpinnerConfig(size: .big, primaryColor: color, secondaryColor: color)
        spinnerView.setUpWith(spinnerConfig)
        spinnerContainerView.alpha = 0
        view.sendSubviewToBack(spinnerContainerView)
    }
}

// MARK: Keyboard methods.
extension MLCardFormViewController {
    private func setupKeyboardNotifications() {
        let notificationCenter = NotificationCenter.default
        notificationCenter.addObserver(self, selector: #selector(keyboardDidChange), name: UIResponder.keyboardWillHideNotification, object: nil)
        notificationCenter.addObserver(self, selector: #selector(keyboardDidChange), name: UIResponder.keyboardWillChangeFrameNotification, object: nil)
    }

    private func removeKeyboardNotifications() {
        NotificationCenter.default.removeObserver(self)
    }

    @objc func keyboardDidChange(notification: Notification) {
        if let userInfo = notification.userInfo, let keyboardScreenEndFrame = (userInfo[UIResponder.keyboardFrameEndUserInfoKey] as? NSValue)?.cgRectValue {
            let keyboardViewEndFrame = view.convert(keyboardScreenEndFrame, from: view.window)
            var safeArea: CGFloat = 0
            let deltaBottomMargin: CGFloat = viewModel.isSmallDevice() ? 0.98 :  1.1
            if #available(iOS 11.0, *) {
                safeArea = view.safeAreaInsets.bottom
            }
            let bottomConstraintConstant = (notification.name == UIResponder.keyboardWillHideNotification) ? 0.0 : keyboardViewEndFrame.height + cardFieldHeight / deltaBottomMargin - safeArea
            UIView.animate(withDuration: 0.3) { [weak self] in
                guard let self = self else { return }
                self.containerBottomConstraint.constant = bottomConstraintConstant
                self.view.layoutIfNeeded()
            }
        }
        getKeyboardSize(notification)
    }

    private func getKeyboardSize(_ notification: Notification) {
        guard viewModel.measuredKeyboardSize == CGRect.zero,
            let userInfo = notification.userInfo,
            let keyboardScreenEndFrame = (userInfo[UIResponder.keyboardFrameEndUserInfoKey] as? NSValue)?.cgRectValue
            else { return }
        viewModel.measuredKeyboardSize = keyboardScreenEndFrame
    }
}

// MARK: UICollectionView methods.
extension MLCardFormViewController: UICollectionViewDelegateFlowLayout, UICollectionViewDataSource {
    public func collectionView(_ collectionView: UICollectionView, layout collectionViewLayout: UICollectionViewLayout, sizeForItemAt indexPath: IndexPath) -> CGSize {
        return CGSize(width: collectionView.frame.size.width - cardFieldCellInset * 2, height: collectionView.frame.size.height)
    }
    
    public func collectionView(_ collectionView: UICollectionView, numberOfItemsInSection section: Int) -> Int {
        return viewModel.cardFormFields?.count ?? 0
    }
    
    public func collectionView(_ collectionView: UICollectionView, cellForItemAt indexPath: IndexPath) -> UICollectionViewCell {
        if let cell = collectionView.dequeueReusableCell(withReuseIdentifier: MLCardFormFieldCell.cellIdentifier, for: indexPath) as? MLCardFormFieldCell {
            cell.cardFormFields = viewModel.cardFormFields?[indexPath.item]
            return cell
        }
        return UICollectionViewCell()
    }
}

// MARK: MLCardFormFieldNotifierProtocol
extension MLCardFormViewController: MLCardFormFieldNotifierProtocol {
    func didChangeValue(newValue: String?, from: MLCardFormField) {
        guard let newValue = newValue else { return }
        guard let fieldId = MLCardFormFields(rawValue: from.property.fieldId()) else { return }
        
        switch fieldId {
        case MLCardFormFields.cardNumber:
            self.viewModel.tempTextField.input.text = newValue
            if newValue.count == 6 {
                getCardData(binNumber: newValue)
            } else if newValue.count == 5 {
                shouldUpdateCard(cardUI: DefaultCardUIHandler())
                shouldUpdateAppBarTitle(paymentTypeId: AppBar.Generic.rawValue)
            }
            viewModel.cardDataHandler.number = newValue

        case MLCardFormFields.name:
            viewModel.cardDataHandler.name = newValue

        case MLCardFormFields.expiration:
            viewModel.cardDataHandler.expiration = from.getValue() ?? newValue

        case MLCardFormFields.securityCode:
            viewModel.cardDataHandler.securityCode = newValue

        case MLCardFormFields.identificationTypesPicker:
            if let defaultCardDataHandler = viewModel.cardDataHandler as? DefaultCardDataHandler,
                defaultCardDataHandler.identificationType != newValue {
                viewModel.updateIDNumberFieldValue(value: newValue)
                defaultCardDataHandler.identificationType = newValue
                defaultCardDataHandler.identificationNumber = ""
            }

        case MLCardFormFields.identificationTypeNumber:
            if let defaultCardDataHandler = viewModel.cardDataHandler as? DefaultCardDataHandler {
                defaultCardDataHandler.identificationNumber = newValue
            }
        }
        if viewModel.updateProgressWithCompletion {
            updateProgressFromField(from)
        }
    }
    
    func didBeginEditing(from: MLCardFormField) {
        guard let fieldId = MLCardFormFields(rawValue: from.property.fieldId()) else { return }
        trackScreen(fieldId: fieldId)
        scrollCollectionViewToCardFormField(from)
        
        switch fieldId {
        case MLCardFormFields.name:
            viewModel.cardDataHandler.name = from.getValue() ?? ""
        case MLCardFormFields.securityCode:
            cardDrawer?.showSecurityCode()
        case MLCardFormFields.identificationTypesPicker:
            cardDrawer?.show()
            if let defaultCardDataHandler = viewModel.cardDataHandler as? DefaultCardDataHandler,
                let identificationType = from.getValue() {
                defaultCardDataHandler.identificationType = identificationType
            }
        case MLCardFormFields.identificationTypeNumber:
            cardDrawer?.show()
            if let defaultCardDataHandler = viewModel.cardDataHandler as? DefaultCardDataHandler,
                let identificationNumber = from.getValue() {
                defaultCardDataHandler.identificationNumber = identificationNumber
            }
        default:
            cardDrawer?.show()
        }
        if !viewModel.updateProgressWithCompletion {
            updateProgressFromField(from)
        }
    }
    
    func shouldNext(from: MLCardFormField) {
        let returnValue = viewModel.isCardNumberFieldAndIsMissingCardData(cardFormField: from)
        if returnValue.isCardNumberMissingCardData, let currentBin = returnValue.currentBin {
            getCardData(binNumber: currentBin, showProggressAndSnackBar: true)
            return
        }
        if viewModel.isSecurityCodeFieldAndIsMissingExpiration(cardFormField: from) {
            return
        }

        viewModel.focusCardFormFieldWithOffset(cardFormField: from, offset: 1)
        if viewModel.isLastField(cardFormField: from) {
            // TODO: Dar de alta la tarjeta
            from.resignFocus()
            if viewModel.shouldShowIssuersScreen() {
                setupIssuersScreen()
            } else {
                addCard()
            }
        }
    }
    
    func shouldBack(from: MLCardFormField) {
        viewModel.focusCardFormFieldWithOffset(cardFormField: from, offset: -1)
    }
}

// MARK: IssuerSelectedProtocol
extension MLCardFormViewController: IssuerSelectedProtocol {
    func userDidSelectIssuer(issuer: MLCardFormIssuer, controller: UIViewController) {
        viewModel.setIssuer(issuer: issuer)
        if let imageURL = issuer.imageUrl {
            viewModel.updateCardIssuerImage(imageURL: imageURL)
        }
        dismiss(animated: true) { [weak self] in
            self?.addCard()
        }
    }

    func userDidCancel(controller: UIViewController) {
        controller.dismiss(animated: true, completion: nil)
        if let field = viewModel.cardFormFields?.last?.last {
            field.doFocus()
        }
    }
}

// MARK: MLCardFormViewModelProtocol
extension MLCardFormViewController: MLCardFormViewModelProtocol {
    
    func shouldUpdateFields(remoteSettings: [MLCardFormFieldSetting]) {
        DispatchQueue.main.async { [weak self] in
            guard let self = self else { return }
            self.viewModel.tempTextField.doFocus()
            self.removeKeyboardNotifications()
            // Update fields array and collectionview
            self.viewModel.updateCardFormFields(remoteSettings, notifierProtocol: self)
            self.cardFieldCollectionView?.reloadData()
            self.cardFieldCollectionView?.layoutIfNeeded()
            // Clear expiration date and CVV
            self.viewModel.cardDataHandler.expiration = ""
            self.viewModel.cardDataHandler.securityCode = ""
            // Set focus on new reloaded field
            if let field = self.viewModel.cardFormFields?.first?.first {
                field.doFocus()
            }
            self.setupKeyboardNotifications()
        }
    }

    func shouldUpdateCard(cardUI: CardUI) {
        DispatchQueue.main.async { [weak self] in
            guard let self = self else { return }
            self.cardDrawer?.cardUI = cardUI
        }
    }

    func shouldUpdateAppBarTitle(paymentTypeId: String?) {
        DispatchQueue.main.async { [weak self] in
            guard let self = self else { return }
            switch paymentTypeId {
            case AppBar.CreditCard.rawValue:
                self.title = AppBar.CreditCard.title
            case AppBar.DebitCard.rawValue:
                self.title = AppBar.DebitCard.title
            default:
                self.title = AppBar.Generic.title
            }
        }
    }
}

// MARK: Collectionview methods.
private extension MLCardFormViewController {
    func scrollCollectionViewToCardFormField(_ cardFormField: MLCardFormField) {
        guard let index = viewModel.groupIndexOfCardFormField(cardFormField),
            let cardFieldCollectionView = cardFieldCollectionView else { return }
        guard index != currentCellIndex() else {
            return
        }
        //debugPrint("Scrolling collection to \(cardFormField.property.fieldId())")
        let section = 0
        let numberOfItems = cardFieldCollectionView.numberOfItems(inSection: section)
        let safeIndex = max(0, min(numberOfItems - 1, index))
        let indexPath = IndexPath(row: safeIndex, section: section)
        cardFieldCollectionView.scrollToItem(at: indexPath, at: .centeredHorizontally, animated: true)
    }
    
    func currentCellIndex() -> Int {
        guard let collectionView = cardFieldCollectionView else { return 0 }
        let itemWidth = collectionView.frame.size.width - cardFieldCellInset * 2
        let proportionalOffset = collectionView.contentOffset.x / itemWidth
        let index = Int(round(proportionalOffset))
        let numberOfItems = collectionView.numberOfItems(inSection: 0)
        let safeIndex = max(0, min(numberOfItems - 1, index))
        return safeIndex
    }
}

// MARK: Progress methods.
private extension MLCardFormViewController {
    func showProgress() {
        view.bringSubviewToFront(spinnerContainerView)
        UIView.animate(withDuration: 0.5, delay: 0, options: [.curveLinear, .curveEaseInOut],
                       animations: { [weak self] in
                        if let spinnerContainerView = self?.spinnerContainerView {
                            spinnerContainerView.alpha = 1
                            self?.spinnerView?.show()
                        }
        })
    }
    
    func hideProgress(completion: ((Bool) -> Void)? = nil) {
        UIView.animate(withDuration: 0.5, delay: 0, options: [.curveLinear, .curveEaseInOut],
                       animations: { [weak self] in
                        if let spinnerContainerView = self?.spinnerContainerView {
                            spinnerContainerView.alpha = 0
                            self?.spinnerView?.hide()
                        }
            },
                       completion: { [weak self] (_) in
                        if let spinnerContainerView = self?.spinnerContainerView {
                            self?.view.sendSubviewToBack(spinnerContainerView)
                        }
                        completion?(true)
        })
    }
}
