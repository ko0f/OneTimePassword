//
//  OTPToken+Persistence.m
//  Authenticator
//
//  Copyright (c) 2013 Matt Rubin
//
//  Permission is hereby granted, free of charge, to any person obtaining a copy of
//  this software and associated documentation files (the "Software"), to deal in
//  the Software without restriction, including without limitation the rights to
//  use, copy, modify, merge, publish, distribute, sublicense, and/or sell copies of
//  the Software, and to permit persons to whom the Software is furnished to do so,
//  subject to the following conditions:
//
//  The above copyright notice and this permission notice shall be included in all
//  copies or substantial portions of the Software.
//
//  THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND, EXPRESS OR
//  IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF MERCHANTABILITY, FITNESS
//  FOR A PARTICULAR PURPOSE AND NONINFRINGEMENT. IN NO EVENT SHALL THE AUTHORS OR
//  COPYRIGHT HOLDERS BE LIABLE FOR ANY CLAIM, DAMAGES OR OTHER LIABILITY, WHETHER
//  IN AN ACTION OF CONTRACT, TORT OR OTHERWISE, ARISING FROM, OUT OF OR IN
//  CONNECTION WITH THE SOFTWARE OR THE USE OR OTHER DEALINGS IN THE SOFTWARE.
//

#import "OTPToken+Persistence.h"
#import <OneTimePassword/OneTimePassword-Swift.h>


static NSString *const kOTPService = @"me.mattrubin.authenticator.token";


@interface OTPLegacyToken ()
@property (nonatomic, strong) OTPToken *core;
@end


@implementation OTPLegacyToken (Persistence)

+ (instancetype)tokenWithKeychainItemRef:(NSData *)keychainItemRef
{
    OTPLegacyToken *token = nil;
    NSDictionary *result = [self keychainItemForPersistentRef:keychainItemRef];
    if (result) {
        token = [self tokenWithKeychainDictionary:result];
    }
    return token;
}

+ (NSArray *)allTokensInKeychain
{
    NSArray *keychainItems = [self allKeychainItems];
    NSMutableArray *tokens = [NSMutableArray array];
    for (NSDictionary *keychainDict in keychainItems) {
        OTPLegacyToken *token = [self tokenWithKeychainDictionary:keychainDict];
        if (token)
            [tokens addObject:token];
    }
    return tokens;
}

+ (instancetype)tokenWithKeychainDictionary:(NSDictionary *)keychainDictionary
{
    NSData *urlData = keychainDictionary[(__bridge id)kSecAttrGeneric];
    NSData *secretData = keychainDictionary[(__bridge id)kSecValueData];
    NSString *urlString = [[NSString alloc] initWithData:urlData
                                                encoding:NSUTF8StringEncoding];
    NSURL *url = [NSURL URLWithString:urlString];
    OTPLegacyToken *token = [self tokenWithURL:url secret:secretData];
    token.keychainItemRef = keychainDictionary[(__bridge id)(kSecValuePersistentRef)];
    return token;
}


#pragma mark -

- (NSData *)keychainItemRef
{
    return self.core.keychainItemRef;
}

- (void)setKeychainItemRef:(NSData *)keychainItemRef
{
    self.core.keychainItemRef = keychainItemRef;
}

- (BOOL)isInKeychain
{
    return self.core.isInKeychain;
}

- (BOOL)saveToKeychain
{
    NSData *urlData = [self.url.absoluteString dataUsingEncoding:NSUTF8StringEncoding];

    NSMutableDictionary *attributes = [@{(__bridge id)kSecAttrGeneric: urlData} mutableCopy];

    if (self.isInKeychain) {
        return updateKeychainItemForPersistentRefWithAttributes(self.keychainItemRef, attributes);
    } else {
        attributes[(__bridge id)kSecValueData] = self.secret;
        attributes[(__bridge id)kSecAttrService] = kOTPService;

        NSData *persistentRef = addKeychainItemWithAttributes(attributes);

        self.keychainItemRef = persistentRef;
        return !!persistentRef;
    }
}

- (BOOL)removeFromKeychain
{
    if (!self.isInKeychain) return NO;

    BOOL success = deleteKeychainItemForPersistentRef(self.keychainItemRef);

    if (success) {
        [self setKeychainItemRef:nil];
    }
    return success;
}


#pragma mark - Keychain Items

+ (NSDictionary *)keychainItemForPersistentRef:(NSData *)persistentRef
{
    if (!persistentRef) return nil;

    NSDictionary *queryDict = @{(__bridge id)kSecClass: (__bridge id)kSecClassGenericPassword,
                                (__bridge id)kSecValuePersistentRef: persistentRef,
                                (__bridge id)kSecReturnPersistentRef: (id)kCFBooleanTrue,
                                (__bridge id)kSecReturnAttributes: (id)kCFBooleanTrue,
                                (__bridge id)kSecReturnData: (id)kCFBooleanTrue
                                };

    CFTypeRef result = NULL;
    OSStatus resultCode = SecItemCopyMatching((__bridge CFDictionaryRef)(queryDict),
                                              &result);

    return (resultCode == errSecSuccess) ? (__bridge NSDictionary *)(result) : nil;
}

+ (NSArray *)allKeychainItems
{
    NSDictionary *queryDict = @{(__bridge id)kSecClass: (__bridge id)kSecClassGenericPassword,
                                (__bridge id)kSecMatchLimit: (__bridge id)kSecMatchLimitAll,
                                (__bridge id)kSecReturnPersistentRef: (id)kCFBooleanTrue,
                                (__bridge id)kSecReturnAttributes: (id)kCFBooleanTrue,
                                (__bridge id)kSecReturnData: (id)kCFBooleanTrue
                                };

    CFTypeRef result = NULL;
    OSStatus resultCode = SecItemCopyMatching((__bridge CFDictionaryRef)(queryDict),
                                              &result);

    return (resultCode == errSecSuccess) ? (__bridge NSArray *)(result) : nil;
}

@end


NSData * addKeychainItemWithAttributes(NSDictionary *attributes)
{
    NSMutableDictionary *mutableAttributes = [attributes mutableCopy];
    mutableAttributes[(__bridge __strong id)kSecClass] = (__bridge id)kSecClassGenericPassword;
    mutableAttributes[(__bridge __strong id)kSecReturnPersistentRef] = (__bridge id)kCFBooleanTrue;
    // Set a random string for the account name.
    // We never query by or display this value, but the keychain requires it to be unique.
    if (!mutableAttributes[(__bridge __strong id)kSecAttrAccount])
        mutableAttributes[(__bridge __strong id)kSecAttrAccount] = [[NSUUID UUID] UUIDString];

    CFTypeRef result = NULL;
    OSStatus resultCode = SecItemAdd((__bridge CFDictionaryRef)(mutableAttributes),
                                     &result);

    return (resultCode == errSecSuccess) ? (__bridge NSData *)(result) : nil;
}

BOOL updateKeychainItemForPersistentRefWithAttributes(NSData *persistentRef, NSDictionary *attributesToUpdate)
{
    NSDictionary *queryDict = @{(__bridge id)kSecClass: (__bridge id)kSecClassGenericPassword,
                                (__bridge id)kSecValuePersistentRef: persistentRef,
                                };

    OSStatus resultCode = SecItemUpdate((__bridge CFDictionaryRef)(queryDict),
                                        (__bridge CFDictionaryRef)(attributesToUpdate));

    return (resultCode == errSecSuccess);
}


BOOL deleteKeychainItemForPersistentRef(NSData *persistentRef)
{
    NSDictionary *queryDict = @{(__bridge id)kSecClass: (__bridge id)kSecClassGenericPassword,
                                (__bridge id)kSecValuePersistentRef: persistentRef,
                                };

    OSStatus resultCode = SecItemDelete((__bridge CFDictionaryRef)(queryDict));

    return (resultCode == errSecSuccess);
}
