//
//  CauseEffectBipartiteGraph.swift
//  CauseEffectBipartiteGraph
//
//  Created by 张 家豪 on 2018/3/16.
//  Copyright © 2018年 张 家豪. All rights reserved.
//

import Foundation

/**
 因果二分图的实现类
 通过给定部分左结点，推断右结点到达的概率
 可通过新给定的证据（多个左结点->固定右结点）训练，并调整整个二分图的数据，从而影响下次推断的结论
 使用方法：1.实例化该类
 2.通过load加载数据
 3.通过train进行训练，或通过probability来进行推断
 4.通过package将新的图结构封装，并存储以便下次使用
 */
public class CauseEffectBipartiteGraph {
    private var leftNodes = [String: LeftNode]()
    private var rightNodes = [String: RightNode]()
    
    public init() {
    }
    
    /**
     数据加载的方法
     给定因果二分图的json字符串数据，及全部右结点标识。该方法将根据这些数据重建整个二分图结构。
     */
    public func load(jsonString: String?, rightNodeNames: [String]) {
        clean()
        
        for rightNodeName in rightNodeNames {
            self.rightNodes[rightNodeName] = RightNode(rightNodeName)
        }
        
        guard let _jsonString = jsonString else {
            // 未被训练过的结构
            return
        }
        
        let jsonData: Data = _jsonString.data(using: .utf8)!
        
        guard let data = (try? JSONSerialization.jsonObject(with: jsonData, options: .mutableContainers)) as? [String: Any] else {
            fatalError("CauseEffectBipartiteGraph loading data error")
        }
        
        guard let leftNodes = data["LeftNode"] as? [[String: Any]] else {
            return
        }
        for leftNode in leftNodes {
            let newNode = LeftNode(leftNode["name"] as! String)
            let rightNodes = leftNode["rightNodes"] as! [[String: Any]]
            for rightNode in rightNodes {
                guard let target = self.rightNodes[rightNode["name"] as! String] else {
                    fatalError("CauseEffectBipartiteGraph loading data no rightnode target found")
                }
                newNode.addLines(count: rightNode["count"] as! Int, to: target)
            }
            self.leftNodes[newNode.identifier] = newNode
        }
        
    }
    
    /**
     通过训练调整图的部分数值，从而改进最终的推断结论
     给定证据（多个左结点->固定右结点）
     */
    public func train(_ leftNodeNames: [String], to rightNodeName: String) {
        guard let rightNode = rightNodes[rightNodeName] else {
            return
        }
        for leftNodeName in leftNodeNames {
            if let leftNode = leftNodes[leftNodeName] {
                leftNode.addLine(to: rightNode)
            }
            else {
                let newNode = LeftNode(leftNodeName)
                newNode.addLine(to: rightNode)
                leftNodes[leftNodeName] = newNode
            }
        }
        
    }
    
    /**
     根据现有图得出推断结论
     给定多个事件（多个左结点）
     返回结论（右结点标识）
     */
    public func probability(withNames leftNodeNames: [String]) -> String {
        var leftNodes = [LeftNode]()
        for name in leftNodeNames {
            guard let leftNode = self.leftNodes[name] else {
                continue
            }
            leftNodes.append(leftNode)
        }
        return probability(withNodes: leftNodes)
    }
    
    /**
     根据现有图得出推断结论
     给定多个事件（多个左结点）
     返回结论（右结点标识）及概率 
     */
    public func probabilityWithDetail(withNames leftNodeNames: [String]) -> (String, Float) {
        var leftNodes = [LeftNode]()
        for name in leftNodeNames {
            guard let leftNode = self.leftNodes[name] else {
                continue
            }
            leftNodes.append(leftNode)
        }
        return probabilityWithDetail(withNodes: leftNodes)
    }
    
    /**
     将整个图的数据进行封装，返回封装后的json字符串
     */
    public func package() -> String {
        var response = [String: Any]()
        var leftNodes = [[String: Any]]()
        for leftNode in self.leftNodes.values {
            var dict = [String: Any]()
            dict["name"] = leftNode.identifier
            dict["count"] = leftNode.count
            var rightNodes = [[String: Any]]()
            for rightNodeName in leftNode.lines.keys {
                var rightNode = [String: Any]()
                rightNode["name"] = rightNodeName.identifier
                rightNode["count"] = leftNode.lines[rightNodeName]
                rightNodes.append(rightNode)
            }
            dict["rightNodes"] = rightNodes
            leftNodes.append(dict)
        }
        response["LeftNode"] = leftNodes
        let data = try? JSONSerialization.data(withJSONObject: response, options: JSONSerialization.WritingOptions.prettyPrinted)
        let jsonString = String(data: data!, encoding: String.Encoding(rawValue: String.Encoding.utf8.rawValue))
        return jsonString!
    }
    
    func probability(withNodes leftNodes: [LeftNode]) -> String {
        var probabilities = [RightNode: Float]()
        for leftNode in leftNodes {
            probabilities = probabilities + leftNode.probabilities()
        }
        var best: Float = 0
        var bestk = RightNode("")
        for (key, value) in probabilities {
            if value > best {
                best = value
                bestk = key
            }
        }
        return bestk.identifier
    }
    
    func probabilityWithDetail(withNodes leftNodes: [LeftNode]) -> (String, Float) {
        var probabilities = [RightNode: Float]()
        for leftNode in leftNodes {
            probabilities = probabilities + leftNode.probabilities()
        }
        var best: Float = 0
        var bestk = RightNode("")
        for (key, value) in probabilities {
            if value > best {
                best = value
                bestk = key
            }
        }
        // best/Float(leftNodes.count) 表示平均每个左结点的推断概率
        return (bestk.identifier, best/Float(leftNodes.count))
    }
    
    private func clean() {
        self.leftNodes = [String: LeftNode]()
        self.rightNodes = [String: RightNode]()
    }
}

/**
 因果二分图用到的左结点数据结构类
 */
class LeftNode {
    /* 该结点的标识字符串，应保证所有结点不重复 */
    var identifier: String!
    /* 与该结点有连接的所有右结点 */
    private var rightNodes = [RightNode]()
    /* 包含该结点的总证据数量 */
    private(set) var count: Int = 0
    /* 连接的所有右结点的边的集合 */
    private(set) var lines = [RightNode: Int]()
    
    init(_ identifier: String) {
        self.identifier = identifier
    }
    
    /**
     添加count条新的边，当该边存在则增加边上记录的值
     */
    func addLines(count: Int, to rightNode: RightNode) {
        self.count += count
        if self.rightNodes.contains(rightNode) {
            self.lines[rightNode]! += count
        }
        else {
            self.rightNodes.append(rightNode)
            self.lines[rightNode] = count
        }
    }
    func addLine(to rightNode: RightNode) {
        addLines(count: 1, to: rightNode)
    }
    
    /**
     获取该结点到某一给定右结点的概率
     */
    func probability(to rightNode: RightNode) -> Float {
        guard let value = lines[rightNode] else {
            print("RightNode not exist")
            return 0
        }
        return Float(value)/Float(count)
    }
    
    /**
     获取该结点到所有右结点的概率
     */
    func probabilities() -> [RightNode: Float] {
        var response = [RightNode: Float]()
        for rightNode in rightNodes {
            let value = lines[rightNode]!
            response[rightNode] = Float(value)/Float(count)
        }
        return response
    }
}

/**
 因果二分图用到的右结点数据结构类
 */
class RightNode: Hashable, CustomStringConvertible {
    /* 该结点的标识字符串，应保证所有结点不重复 */
    var identifier: String!
    
    init(_ identifier: String) {
        self.identifier = identifier
    }
    
    var hashValue: Int {
        return self.identifier.hashValue
    }
    
    static func ==(lhs: RightNode, rhs: RightNode) -> Bool {
        return lhs.hashValue == rhs.hashValue
    }
    
    var description: String {
        return identifier
    }
}

private func + (lhs: [RightNode: Float], rhs: [RightNode: Float]) -> [RightNode: Float] {
    var response = [RightNode: Float]()
    for key in lhs.keys {
        var vr = Float(0)
        if rhs[key] != nil {
            vr = rhs[key]!
        }
        response[key] = lhs[key]! + vr
    }
    for key in rhs.keys {
        if lhs[key] == nil {
            response[key] = rhs[key]!
        }
    }
    return response
}

