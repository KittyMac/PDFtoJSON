import Foundation
import Spanker
import Hitch

public struct Matrix3x3 {
    var m11: Double = 1.0
    var m12: Double = 0.0
    var m13: Double = 0.0
    var m21: Double = 0.0
    var m22: Double = 1.0
    var m23: Double = 0.0
    var m31: Double = 0.0
    var m32: Double = 0.0
    var m33: Double = 1.0
    
    public init() {
        
    }
    
    public init(m11: Double, m12: Double, m13: Double, m21: Double, m22: Double, m23: Double, m31: Double, m32: Double, m33: Double) {
        self.m11 = m11
        self.m12 = m12
        self.m13 = m13
        self.m21 = m21
        self.m22 = m22
        self.m23 = m23
        self.m31 = m31
        self.m32 = m32
        self.m33 = m33
    }

    public func multiply(by other: Matrix3x3) -> Matrix3x3 {
        let result = Matrix3x3(
            m11: m11 * other.m11 + m12 * other.m21 + m13 * other.m31,
            m12: m11 * other.m12 + m12 * other.m22 + m13 * other.m32,
            m13: m11 * other.m13 + m12 * other.m23 + m13 * other.m33,
            m21: m21 * other.m11 + m22 * other.m21 + m23 * other.m31,
            m22: m21 * other.m12 + m22 * other.m22 + m23 * other.m32,
            m23: m21 * other.m13 + m22 * other.m23 + m23 * other.m33,
            m31: m31 * other.m11 + m32 * other.m21 + m33 * other.m31,
            m32: m31 * other.m12 + m32 * other.m22 + m33 * other.m32,
            m33: m31 * other.m13 + m32 * other.m23 + m33 * other.m33
        )
        return result
    }

    public func translate(by translation: (x: Double, y: Double)) -> Matrix3x3 {
        let translationMatrix = Matrix3x3(
            m11: 1.0, m12: 0.0, m13: translation.x,
            m21: 0.0, m22: 1.0, m23: translation.y,
            m31: 0.0, m32: 0.0, m33: 1.0
        )
        return self.multiply(by: translationMatrix)
    }

    public func transform(x: Double, y: Double) -> (x: Double, y: Double) {
        let x = m11 * x + m12 * y + m13
        let y = m21 * x + m22 * y + m23
        return (x, y)
    }

    public func printMatrix() {
        print("\(m11), \(m12), \(m13)")
        print("\(m21), \(m22), \(m23)")
        print("\(m31), \(m32), \(m33)")
    }
}
