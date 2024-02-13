import UIKit
import DGCharts

import MobileCoreServices
import UniformTypeIdentifiers

class ChartVC: UIViewController, ChartViewDelegate {
    private var shownFiles: [String] = []
    private var shownFileNames: [String: String] = [:]
    private var lastChartNumber: Int = 0
    
    private let tableView = UITableView()
    private var costLabel: UILabel!
    private var dateLabel: UILabel!
    
    private var chart: LineChartView!
    private var dataSets: [LineChartDataSet] = []
    private var allChartEntries: [[ChartDataEntry]] = []
    private var chartColors: [UIColor] = []
    
    private var availableChartColors: Set = [UIColor.systemRed, .systemGreen, .systemBlue, .systemPurple, .systemPink, .systemBrown]
    
    private var intervalButtons: [UIButton]!
    private var intervalButtonsStackView: UIStackView!
    
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
    
    override func viewDidLayoutSubviews() {
        setCostLabelConstraints()
        setDateLabelConstraints()
        setChartConstraints()
        setIntervalButtonsConstraints()
    }
    
    func chartValueSelected(_ chartView: ChartViewBase, entry: ChartDataEntry, highlight: Highlight) {
        costLabel.text = String(entry.y) + " hours"
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
    
    private func setupShownDataSet(for interval: ChartInterval) {
        DispatchQueue.global(qos: .userInitiated).async { [weak self] in
            guard let self = self else { return }
            
            let pointsNumberToDraw = 40
            
            var dateFrom: Date!
            switch interval {
            case .day:       dateFrom = Calendar.current.date(byAdding: .day,           value: -1,  to: Date())
            case .week:      dateFrom = Calendar.current.date(byAdding: .weekOfYear,    value: -1,  to: Date())
            case .month:     dateFrom = Calendar.current.date(byAdding: .month,         value: -1,  to: Date())
            case .sixMonths: dateFrom = Calendar.current.date(byAdding: .month,         value: -6,  to: Date())
            case .year:      dateFrom = Calendar.current.date(byAdding: .year,          value: -1,  to: Date())
            case .all:       dateFrom = Calendar.current.date(byAdding: .year,          value: -10, to: Date())
            }
            let TimestampFrom = Int(dateFrom.timeIntervalSince1970)
            
            for i in 0..<allChartEntries.count {
                let firstAppropriateIndex: Int = self.allChartEntries[i].firstIndex { TimestampFrom <= Int($0.x) } ?? 0
                let endAppropriateIndex: Int = self.allChartEntries[i].endIndex
                
                let entriesInInterval = self.allChartEntries[i][firstAppropriateIndex..<endAppropriateIndex]
                
                let resolution =
                    entriesInInterval.count > pointsNumberToDraw ? entriesInInterval.count / pointsNumberToDraw : 1
                
                let entriesToShow = entriesInInterval.enumerated().compactMap
                    { $0.offset.isMultiple(of: resolution) ? $0.element : nil }
                 
                let evenlyDistributedEntries = entriesToShow.enumerated().map
                    { ChartDataEntry(x: Double($0.offset), y: $0.element.y, data: $0.element.x) }
                
                DispatchQueue.main.async { [weak self] in
                    guard let self = self else { return }
                    self.dataSets[i].replaceEntries(evenlyDistributedEntries)
                    self.chart.data = LineChartData(dataSets: self.dataSets)
                }
            }
            
        }
    }
    
    func setupDataSet(xValues: [Double], yValues: [Double]) {
        DispatchQueue.global(qos: .userInitiated).async { [weak self] in
            guard let self = self else { return }
            guard xValues.count == yValues.count else { fatalError() }
            
            var entries: [ChartDataEntry] = []
            
            for (i, value) in yValues.enumerated() {
                entries.append(ChartDataEntry(x: Double(xValues[i]), y: value))
            }
            
            self.allChartEntries.append(entries)
            
            let dataSet = LineChartDataSet()
            dataSet.drawCirclesEnabled = false
            dataSet.mode = .cubicBezier
            let color = availableChartColors.first ?? .black
            availableChartColors.remove(color)
            chartColors.append(color)
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
            self.dataSets.append(dataSet)
            let interval = ChartInterval.month
            self.setupShownDataSet(for: interval)
        }
    }
    
}

extension ChartVC: UIDocumentPickerDelegate {
    
    public func documentPicker(_ controller: UIDocumentPickerViewController, didPickDocumentsAt urls: [URL]) {
        guard let myURL = urls.first else {
            return
        }
        guard !shownFiles.contains(where: { $0 == myURL.relativePath }) else { return }
        
        guard myURL.startAccessingSecurityScopedResource() else {
            return
        }
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
        
        print(parsedCSV)
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
            let color = chartColors[indexPath.row]
            chartColors.remove(at: indexPath.row)
            availableChartColors.insert(color)
            dataSets.remove(at: indexPath.row)
            allChartEntries.remove(at: indexPath.row)
            self.chart.data = LineChartData(dataSets: self.dataSets)
        }
    }
    
}

// - MARK: Selectors
extension ChartVC {
    
    @objc private func intervalButtonTouchUpInside(sender: UIButton!) {
        guard !allChartEntries.isEmpty else { return }
        
        intervalButtons.forEach { $0.backgroundColor = .clear }
        sender.backgroundColor = #colorLiteral(red: 0.8864082694, green: 0.8902869821, blue: 0.8942552209, alpha: 1)
        
        guard let title = sender.currentTitle, let interval = ChartInterval(rawValue: title)
        else { fatalError("Non existing interval")}
        
        setupShownDataSet(for: interval)
    }
    
    @objc func selectFiles() {
        let types = UTType.types(tag: "csv",
                                 tagClass: UTTagClass.filenameExtension,
                                 conformingTo: nil)
        let documentPickerController = UIDocumentPickerViewController(
                forOpeningContentTypes: types)
        documentPickerController.delegate = self
        self.present(documentPickerController, animated: true, completion: nil)
    }
    
}

// - Setting constraints
extension ChartVC {
    
    func setCostLabelConstraints() {
        costLabel.translatesAutoresizingMaskIntoConstraints = false
        costLabel.topAnchor.constraint(equalTo: view.safeAreaLayoutGuide.topAnchor,
                                       constant: 16).isActive = true
        costLabel.heightAnchor.constraint(equalToConstant: 30).isActive = true
        costLabel.leadingAnchor.constraint(equalTo: view.safeAreaLayoutGuide.leadingAnchor, constant: 0).isActive = true
        costLabel.trailingAnchor.constraint(equalTo: view.safeAreaLayoutGuide.trailingAnchor, constant: 0).isActive = true
    }
    
    func setDateLabelConstraints() {
        dateLabel.translatesAutoresizingMaskIntoConstraints = false
        dateLabel.topAnchor.constraint(equalTo: costLabel.bottomAnchor, constant: 10).isActive = true
        dateLabel.heightAnchor.constraint(equalToConstant: 30).isActive = true
        dateLabel.leadingAnchor.constraint(equalTo: view.leadingAnchor, constant: 0).isActive = true
        dateLabel.trailingAnchor.constraint(equalTo: view.trailingAnchor, constant: 0).isActive = true
    }
    
    func setChartConstraints() {
        chart.translatesAutoresizingMaskIntoConstraints = false
        chart.topAnchor.constraint(equalTo: dateLabel.bottomAnchor, constant: 0).isActive = true
        chart.heightAnchor.constraint(equalToConstant: 300).isActive = true
        chart.leadingAnchor.constraint(equalTo: view.safeAreaLayoutGuide.leadingAnchor, constant: 0).isActive = true
        chart.trailingAnchor.constraint(equalTo: view.safeAreaLayoutGuide.trailingAnchor, constant: 0).isActive = true
    }
    
    func setIntervalButtonsConstraints() {
        intervalButtonsStackView.translatesAutoresizingMaskIntoConstraints = false
        intervalButtonsStackView.topAnchor.constraint(equalTo: chart.bottomAnchor, constant: 10).isActive = true
        intervalButtonsStackView.centerXAnchor.constraint(equalTo: view.centerXAnchor).isActive = true
        intervalButtonsStackView.widthAnchor.constraint(equalTo: view.widthAnchor, constant: -40).isActive = true
        intervalButtonsStackView.heightAnchor.constraint(equalToConstant: 40).isActive = true
    }
}

// - MARK: Adding subviews
extension ChartVC {
    private func addSubviews() {
        addChartView()
        addCostLabel()
        addDateLabel()
        addIntervalButtons()
        addTableView()
    }
    
    private func addChartView() {
        chart = LineChartView()
        chart.backgroundColor = .white
        chart.tintColor = .systemGreen
        
        chart.noDataTextColor = .black
        chart.noDataText = "Need to load data to build a chart"
        chart.noDataFont = .boldSystemFont(ofSize: 10)
        
        chart.xAxis.enabled = false
        chart.leftAxis.enabled = false
        chart.rightAxis.enabled = false
        
        chart.scaleYEnabled = false
        chart.doubleTapToZoomEnabled = false
        
        chart.delegate = self
        view.addSubview(chart)
    }
    
    private func addCostLabel() {
        costLabel = UILabel()
        costLabel.font = .boldSystemFont(ofSize: 32) // UIFont(name: "Arial Bold", size: 32.0)
        costLabel.textColor = .black
        costLabel.textAlignment = .center
        view.addSubview(costLabel)
    }
    
    private func addDateLabel() {
        dateLabel = UILabel()
        dateLabel.font = .systemFont(ofSize: 16) // UIFont(name: "Arial", size: 16.0)
        dateLabel.textColor = .black
        dateLabel.textAlignment = .center
        view.addSubview(dateLabel)
    }
    
    private func addIntervalButtons() {
        intervalButtons = []
        
        for interval in ChartInterval.allCases {
            let button = UIButton()
            button.backgroundColor = .clear
            button.setTitleColor(.black, for: .normal)
            button.setTitle(interval.rawValue, for: .normal)
            button.layer.cornerRadius = 10
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
    }
    
    private func addTableView() {
        tableView.dataSource = self
        tableView.delegate = self
        view.addSubview(tableView)
        tableView.translatesAutoresizingMaskIntoConstraints = false
        tableView.topAnchor.constraint(equalTo: intervalButtonsStackView.bottomAnchor, constant: 16).isActive = true
        tableView.leadingAnchor.constraint(equalTo: view.leadingAnchor, constant: 16).isActive = true
        tableView.trailingAnchor.constraint(equalTo: view.trailingAnchor, constant: -16).isActive = true
        tableView.bottomAnchor.constraint(equalTo: view.safeAreaLayoutGuide.bottomAnchor, constant: -16).isActive = true
    }
    
    // TODO: make all constant like in video from Vasya
    // TODO: make safeAreaLayoutGuide where need to
}
