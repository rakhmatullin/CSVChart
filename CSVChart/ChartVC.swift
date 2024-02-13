import UIKit
import DGCharts

import MobileCoreServices
import UniformTypeIdentifiers

final class ChartVC: UIViewController {
    private var shownFiles: [String] = []
    private var shownFileNames: [String: String] = [:]
    private var lastChartNumber: Int = 0
    private var chartInfos: [ChartInfo] = []
    private var availableChartColors: Set = [UIColor.systemRed, .systemGreen, .systemBlue, .systemPurple, .systemPink, .systemBrown]
    
    private let tableView = UITableView()
    private let valueLabel = UILabel()
    private let dateLabel = UILabel()
    private let chartView = LineChartView()
    private var intervalButtons: [UIButton] = []
    private var intervalButtonsStackView = UIStackView()
    
    private struct ChartInfo {
        let dataSet: LineChartDataSet
        let chartEntries: [ChartDataEntry]
        let chartColor: UIColor
    }
    
    private enum ChartInterval: String, CaseIterable {
        case day            = "D"
        case week           = "W"
        case month          = "M"
        case sixMonths      = "6M"
        case year           = "1Y"
        case all            = "All"
    }
    
    override func viewDidLoad() {
        super.viewDidLoad()
        view.backgroundColor = .systemBackground
        addSubviews()
    }
    
}

// MARK: - Setting chart data
extension ChartVC {
    
    private func setupShownDataSet(for interval: ChartInterval) {
        DispatchQueue.global(qos: .userInitiated).async { [weak self] in
            guard let self = self else { return }
            
            let pointsNumberToDraw = 40
            let dateFrom: Date!
            switch interval {
            case .day:       dateFrom = Calendar.current.date(byAdding: .day,           value: -1,  to: Date())
            case .week:      dateFrom = Calendar.current.date(byAdding: .weekOfYear,    value: -1,  to: Date())
            case .month:     dateFrom = Calendar.current.date(byAdding: .month,         value: -1,  to: Date())
            case .sixMonths: dateFrom = Calendar.current.date(byAdding: .month,         value: -6,  to: Date())
            case .year:      dateFrom = Calendar.current.date(byAdding: .year,          value: -1,  to: Date())
            case .all:       dateFrom = Calendar.current.date(byAdding: .year,          value: -10, to: Date())
            }
            let timestampFrom = Int(dateFrom.timeIntervalSince1970)
            
            for i in 0..<chartInfos.count {
                let firstAppropriateIndex = chartInfos[i].chartEntries.firstIndex { timestampFrom <= Int($0.x) } ?? 0
                let endAppropriateIndex = chartInfos[i].chartEntries.endIndex
                let entriesInInterval = chartInfos[i].chartEntries[firstAppropriateIndex..<endAppropriateIndex]
                let resolution =
                    entriesInInterval.count > pointsNumberToDraw ? entriesInInterval.count / pointsNumberToDraw : 1
                let entriesToShow = entriesInInterval.enumerated().compactMap
                    { $0.offset.isMultiple(of: resolution) ? $0.element : nil }
                let evenlyDistributedEntries = entriesToShow.enumerated().map
                    { ChartDataEntry(x: Double($0.offset), y: $0.element.y, data: $0.element.x) }
                DispatchQueue.main.async { [weak self] in
                    guard let self = self else { return }
                    chartInfos[i].dataSet.replaceEntries(evenlyDistributedEntries)
                    self.chartView.data = LineChartData(dataSets: chartInfos.map { $0.dataSet })
                }
            }
        }
    }
    
    func setupDataSet(xValues: [Double], yValues: [Double]) {
        DispatchQueue.global(qos: .userInitiated).async { [weak self] in
            guard let self = self, xValues.count == yValues.count else { fatalError() }
            
            var entries: [ChartDataEntry] = []
            for (i, value) in yValues.enumerated() {
                entries.append(ChartDataEntry(x: Double(xValues[i]), y: value))
            }
            let dataSet = LineChartDataSet()
            dataSet.drawCirclesEnabled = false
            dataSet.mode = .cubicBezier
            let color = availableChartColors.first ?? .black
            availableChartColors.remove(color)
            dataSet.setColor(color)
            dataSet.drawValuesEnabled = true
            dataSet.highlightColor = .lightGray
            dataSet.drawHorizontalHighlightIndicatorEnabled = false
            dataSet.lineWidth = 1.5
            dataSet.fillAlpha = 0.1
            dataSet.drawFilledEnabled = true
            let gradient: CGGradient! = CGGradient(
                colorsSpace: nil,
                colors: [UIColor.white.cgColor, color.cgColor] as CFArray,
                locations: [0.0, 1]
            )
            dataSet.fill = LinearGradientFill(gradient: gradient, angle: 90)
            chartInfos.append(ChartInfo(dataSet: dataSet, chartEntries: entries, chartColor: color))
            self.setupShownDataSet(for: ChartInterval.month)
        }
    }
    
}

extension ChartVC: UIDocumentPickerDelegate {
    public func documentPicker(_ controller: UIDocumentPickerViewController, didPickDocumentsAt urls: [URL]) {
        guard 
            let myURL = urls.first,
            !shownFiles.contains(where: { $0 == myURL.relativePath }),
            myURL.startAccessingSecurityScopedResource()
        else { return }
        defer { myURL.stopAccessingSecurityScopedResource() }
        
        let parsedCSV: [String]
        do {
            let contents = try String(contentsOf: myURL)
            parsedCSV = contents.components(separatedBy: "\n")
                .map{ $0.components(separatedBy: ",")[0] }
        }
        catch {
            return
        }
        
        shownFiles.append(myURL.relativePath)
        lastChartNumber += 1
        shownFileNames[myURL.relativePath] = "Chart " + String(lastChartNumber)
        tableView.reloadData()
        
        let dateFormatter = DateFormatter()
        dateFormatter.dateFormat = "yyyy-MM-dd HH:mm:ss"
        var timestamps: [TimeInterval] = []
        var values: [Double] = []
        for fileLine in parsedCSV {
            let lineComponents = fileLine.components(separatedBy: ";")
            if lineComponents.count == 2,
               let date = dateFormatter.date(from: lineComponents[0]),
               let value = Double(lineComponents[1])
            {
                timestamps.append(date.timeIntervalSince1970)
                values.append(value)
            }
        }
        setupDataSet(xValues: timestamps, yValues: values)
    }
}

// - MARK: ChartViewDelegate
extension ChartVC: ChartViewDelegate {
    func chartValueSelected(_ chartView: ChartViewBase, entry: ChartDataEntry, highlight: Highlight) {
        valueLabel.text = String(entry.y) + " hours"
        if let timeResult = entry.data as? Double {
            let date = Date(timeIntervalSince1970: timeResult)
            let dateFormatter = DateFormatter()
            dateFormatter.timeStyle = DateFormatter.Style.medium
            dateFormatter.dateStyle = DateFormatter.Style.medium
            dateFormatter.timeZone = .current
            let localDate = dateFormatter.string(from: date)
            dateLabel.text = localDate
        }
    }
}

// - MARK: UITableViewDataSource + UITableViewDelegate
extension ChartVC: UITableViewDataSource, UITableViewDelegate {
    
    func tableView(_ tableView: UITableView, numberOfRowsInSection section: Int) -> Int {
        shownFiles.count + 1
    }
    
    func tableView(_ tableView: UITableView, cellForRowAt indexPath: IndexPath) -> UITableViewCell {
        guard indexPath.row <= shownFiles.count else { return UITableViewCell() }
        
        let cell = UITableViewCell()
        cell.textLabel?.text = indexPath.row == shownFiles.count ? "Add chart" : shownFileNames[shownFiles[indexPath.row]]
        return cell
    }
    
    func tableView(_ tableView: UITableView, didSelectRowAt indexPath: IndexPath) {
        tableView.deselectRow(at: indexPath, animated: true)
        if indexPath.row == shownFiles.count {
            selectFiles()
        } else {
            guard indexPath.row < shownFiles.count else { return }
            shownFiles.remove(at: indexPath.row)
            tableView.reloadData()
            availableChartColors.insert(chartInfos[indexPath.row].chartColor)
            chartInfos.remove(at: indexPath.row)
            self.chartView.data = LineChartData(dataSets: chartInfos.map { $0.dataSet })
        }
    }
    
}

// - MARK: Selectors
extension ChartVC {
    
    @objc private func intervalButtonTouchUpInside(sender: UIButton!) {
        guard !chartInfos.isEmpty else { return }
        
        intervalButtons.forEach { $0.backgroundColor = .clear }
        sender.backgroundColor = #colorLiteral(red: 0.8864082694, green: 0.8902869821, blue: 0.8942552209, alpha: 1)
        
        guard let title = sender.currentTitle, let interval = ChartInterval(rawValue: title)
        else { fatalError("Non existing interval")}
        
        setupShownDataSet(for: interval)
    }
    
    @objc func selectFiles() {
        let types = UTType.types(tag: "csv", tagClass: UTTagClass.filenameExtension, conformingTo: nil)
        let documentPickerController = UIDocumentPickerViewController(forOpeningContentTypes: types)
        documentPickerController.delegate = self
        self.present(documentPickerController, animated: true, completion: nil)
    }
    
}

// - MARK: Adding subviews
extension ChartVC {
    
    private func addSubviews() {
        addCostLabel()
        addDateLabel()
        addChartView()
        addIntervalButtons()
        addTableView()
    }
    
    private func addChartView() {
        chartView.backgroundColor = .white
        chartView.tintColor = .systemGreen
        chartView.noDataTextColor = .black
        chartView.noDataText = "Need to load data to build a chart"
        chartView.noDataFont = .boldSystemFont(ofSize: 10)
        chartView.xAxis.enabled = false
        chartView.leftAxis.enabled = false
        chartView.rightAxis.enabled = false
        chartView.scaleYEnabled = false
        chartView.doubleTapToZoomEnabled = false
        chartView.delegate = self
        view.addSubview(chartView)
        chartView.translatesAutoresizingMaskIntoConstraints = false
        chartView.topAnchor.constraint(equalTo: dateLabel.bottomAnchor, constant: 0).isActive = true
        chartView.heightAnchor.constraint(equalToConstant: 300).isActive = true
        chartView.leadingAnchor.constraint(equalTo: view.safeAreaLayoutGuide.leadingAnchor, constant: 0).isActive = true
        chartView.trailingAnchor.constraint(equalTo: view.safeAreaLayoutGuide.trailingAnchor, constant: 0).isActive = true
    }
    
    private func addCostLabel() {
        valueLabel.font = .boldSystemFont(ofSize: 32)
        valueLabel.textColor = .black
        valueLabel.textAlignment = .center
        view.addSubview(valueLabel)
        valueLabel.translatesAutoresizingMaskIntoConstraints = false
        valueLabel.topAnchor.constraint(equalTo: view.safeAreaLayoutGuide.topAnchor, constant: 16).isActive = true
        valueLabel.heightAnchor.constraint(equalToConstant: 30).isActive = true
        valueLabel.leadingAnchor.constraint(equalTo: view.safeAreaLayoutGuide.leadingAnchor).isActive = true
        valueLabel.trailingAnchor.constraint(equalTo: view.safeAreaLayoutGuide.trailingAnchor).isActive = true
    }
    
    private func addDateLabel() {
        dateLabel.font = .systemFont(ofSize: 16)
        dateLabel.textColor = .black
        dateLabel.textAlignment = .center
        view.addSubview(dateLabel)
        dateLabel.translatesAutoresizingMaskIntoConstraints = false
        dateLabel.topAnchor.constraint(equalTo: valueLabel.bottomAnchor, constant: Constants.dateLabelTopOffset).isActive = true
        dateLabel.heightAnchor.constraint(equalToConstant: 30).isActive = true
        dateLabel.leadingAnchor.constraint(equalTo: view.leadingAnchor).isActive = true
        dateLabel.trailingAnchor.constraint(equalTo: view.trailingAnchor).isActive = true
    }
    
    private func addIntervalButtons() {
        for interval in ChartInterval.allCases {
            let button = UIButton()
            button.backgroundColor = .clear
            button.setTitleColor(.black, for: .normal)
            button.setTitle(interval.rawValue, for: .normal)
            button.layer.cornerRadius = Constants.buttonsCornerRadius
            button.layer.borderWidth = 0
            button.layer.borderColor = UIColor.black.cgColor
            button.addTarget(self, action: #selector(intervalButtonTouchUpInside), for: .touchUpInside)
            intervalButtons.append(button)
        }
        intervalButtons[2].backgroundColor = #colorLiteral(red: 0.8864082694, green: 0.8902869821, blue: 0.8942552209, alpha: 1)
        intervalButtonsStackView = UIStackView(arrangedSubviews: intervalButtons)
        intervalButtonsStackView.axis = .horizontal
        intervalButtonsStackView.distribution = .fillEqually
        intervalButtonsStackView.alignment = .fill
        view.addSubview(intervalButtonsStackView)
        intervalButtonsStackView.translatesAutoresizingMaskIntoConstraints = false
        intervalButtonsStackView.topAnchor.constraint(equalTo: chartView.bottomAnchor, constant: Constants.buttonsStackViewTopOffset).isActive = true
        intervalButtonsStackView.centerXAnchor.constraint(equalTo: view.centerXAnchor).isActive = true
        intervalButtonsStackView.widthAnchor.constraint(equalTo: view.widthAnchor, 
                                                        constant: -Constants.buttonsStackViewToSuperviewWidthDiff).isActive = true
        intervalButtonsStackView.heightAnchor.constraint(equalToConstant: Constants.buttonsStackViewHeight).isActive = true
    }
    
    private func addTableView() {
        tableView.dataSource = self
        tableView.delegate = self
        view.addSubview(tableView)
        tableView.translatesAutoresizingMaskIntoConstraints = false
        tableView.topAnchor.constraint(equalTo: intervalButtonsStackView.bottomAnchor, constant: Constants.defaultOffset).isActive = true
        tableView.leadingAnchor.constraint(equalTo: view.leadingAnchor, constant: Constants.defaultOffset).isActive = true
        tableView.trailingAnchor.constraint(equalTo: view.trailingAnchor, constant: -Constants.defaultOffset).isActive = true
        tableView.bottomAnchor.constraint(equalTo: view.safeAreaLayoutGuide.bottomAnchor, constant: -Constants.defaultOffset).isActive = true
    }
    
}

private enum Constants {
    static let defaultOffset = 16.0
    static let dateLabelTopOffset = 10.0
    static let buttonsCornerRadius = 10.0
    static let buttonsStackViewTopOffset = 10.0
    static let buttonsStackViewHeight = 40.0
    static let buttonsStackViewToSuperviewWidthDiff = 40.0
}
