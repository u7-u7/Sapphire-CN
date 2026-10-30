//
//  VerificationCodeDetector.swift
//  Sapphire
//
//  Created by Shariq Charolia on 2026-08-30

#if !SAPPHIRE_FULL_BUILD
import Foundation

enum VerificationCodeDetector {
    // 普通工作编号不能触发自动复制，只有明确的验证码标签才允许提取数字。
    private static let keyword = #"(?:验证码|驗證碼|校验码|校驗碼|动态码|動態碼|短信码|短信碼|一次性密码|一次性密碼|(?<![A-Za-z])(?:otp|passcode|(?:verification|security|authentication|confirmation|login|sign[\s-]?in|one[\s-]?time)\s+(?:code|password))(?![A-Za-z]))"#
    private static let separator = #"[\s:：,，=【】\[\]（）()「」\"'“”‘’—–-]*"#
    private static let code = #"(?<![A-Za-z0-9])([0-9]{4,8})(?![A-Za-z0-9])"#
    private static let patterns = [
        keyword + separator + #"(?:(?:是|为|為|is)\s*)?"# + separator + code,
        code + separator + #"(?:(?:is\s+(?:your|the)\s+(?:[A-Za-z][A-Za-z'-]{0,30}\s+){0,3}|是(?:您的|你的)?\s*))?"# + separator + keyword
    ].compactMap { try? NSRegularExpression(pattern: $0, options: .caseInsensitive) }

    static func find(in text: String) -> String? {
        let range = NSRange(text.startIndex..., in: text)
        for regex in patterns {
            if let match = regex.firstMatch(in: text, range: range),
               let matchRange = Range(match.range(at: 1), in: text) {
                return String(text[matchRange])
            }
        }
        return nil
    }
}
#endif
