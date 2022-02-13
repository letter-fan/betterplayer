// Copyright 2017 The Chromium Authors. All rights reserved.
// Use of this source code is governed by a BSD-style license that can be
// found in the LICENSE file.

#import "BetterPlayerEzDrmAssetsLoaderDelegate.h"

@implementation BetterPlayerEzDrmAssetsLoaderDelegate

NSString *_assetId;

static NSString * const USER_AGENT = @"Mozilla/5.0 (iPhone; CPU iPhone OS 10_3_2 like Mac OS X) AppleWebKit/603.2.4 (KHTML, like Gecko) Version/10.0 Mobile/14F89 Safari/602.1";
static NSString * const URL_SCHEME_NAME = @"skd";
static NSString * const TAG = @"com.playersdk.drm.fps";
static NSString * const CONTENT_TYPE_FIELD_KEY = @"Content-Type";
static NSString * const TYPE_JSON = @"application/json";
static NSString * const GET = @"GET";
static NSString * const POST = @"POST";
static NSString * const USER_AGENT_FIELD_KEY = @"User-Agent";

- (instancetype)init:(NSURL *)certificateURL withLicenseURL:(NSURL *)licenseURL{
    self = [super init];
    _certificateURL = certificateURL;
    _licenseURL = licenseURL;
    return self;
}

/*------------------------------------------
 **
 ** getAppCertificate
 **
 ** returns the apps certificate for authenticating against your server
 ** the example here uses a local certificate
 ** but you may need to edit this function to point to your certificate
 ** ---------------------------------------*/
// - (NSData *)getAppCertificate:(NSString *) String {
//     NSData * certificate = nil;
//     certificate = [NSData dataWithContentsOfURL:_certificateURL];
//     return certificate;
// }

- (NSData *)getFairPlayCertification:(NSError *)error {

    NSHTTPURLResponse *response = nil;
    NSMutableURLRequest *request = [NSMutableURLRequest requestWithURL:_certificateURL];
    request.HTTPMethod = GET;
    [request setValue:USER_AGENT forHTTPHeaderField:USER_AGENT_FIELD_KEY];

    NSData *responseData = [NSURLConnection sendSynchronousRequest:request returningResponse:&response error:&error];

    if (response.statusCode == 200) {
        return responseData;
    }
    return nil;
}


/*------------------------------------------
 **
 ** getContentKeyAndLeaseExpiryFromKeyServerModuleWithRequest
 **
 ** Takes the bundled SPC and sends it to the license server defined at licenseUrl or KEY_SERVER_URL (if licenseUrl is null).
 ** It returns CKC.
 ** ---------------------------------------*/
- (NSData *)getContentKeyAndLeaseExpiryfromKeyServerModuleWithRequest:(NSData *)requestBytes contentIdentifierHost:(NSString *)assetStr
                                                                error:(NSError **)errorOut
{
    NSMutableURLRequest *request = [NSMutableURLRequest requestWithURL:_licenseURL];
    request.HTTPMethod = POST;
    NSString *json = [NSString stringWithFormat:@"{ \"spc\" : \"%@\" }", [requestBytes base64EncodedStringWithOptions:0]];
    NSData *entity = [json dataUsingEncoding:NSUTF8StringEncoding];
    request.HTTPBody = entity;
    [request setValue:TYPE_JSON forHTTPHeaderField:CONTENT_TYPE_FIELD_KEY];

    NSHTTPURLResponse *response = nil;

    NSTimeInterval licenseResponseTime = [NSDate timeIntervalSinceReferenceDate];

    NSData *responseData = [NSURLConnection sendSynchronousRequest:request returningResponse:&response error:errorOut];

    licenseResponseTime = [NSDate timeIntervalSinceReferenceDate] - licenseResponseTime;

    if (!responseData) {
        return nil;
    }

    NSDictionary *dict = [NSJSONSerialization JSONObjectWithData:responseData options:0 error:errorOut];
    if (!dict) {
        return nil;
    }

    NSString *errMessage = dict[@"message"];
    if (errMessage) {
        *errorOut = [NSError errorWithDomain:TAG code:'CKCE' userInfo:@{@"ServerMessage": errMessage}];
        return nil;
    }
    NSString *ckc = dict[@"ckc"];

    if (!ckc) {
        *errorOut = [NSError errorWithDomain:TAG code:'NCKC' userInfo:nil];
        return nil;
    }

    NSData *ckcData = [[NSData alloc] initWithBase64EncodedString:ckc options:0];

    if (!ckcData) {
        *errorOut = [NSError errorWithDomain:TAG code:'ICKC' userInfo:nil];
        return nil;
    }

    return ckcData;
}

- (BOOL)resourceLoader:(AVAssetResourceLoader *)resourceLoader shouldWaitForLoadingOfRequestedResource:(AVAssetResourceLoadingRequest *)loadingRequest
{
    AVAssetResourceLoadingDataRequest *dataRequest = loadingRequest.dataRequest;
    NSURL *url = loadingRequest.request.URL;
    NSError *error = nil;
    BOOL handled = NO;

    if (![[url scheme] isEqual:URL_SCHEME_NAME])
        return NO;

    NSString *assetStr;
    NSData *assetId;
    NSData *requestBytes;

    assetStr = [url host];
    assetId = [NSData dataWithBytes: [assetStr cStringUsingEncoding:NSUTF8StringEncoding] length:[assetStr lengthOfBytesUsingEncoding:NSUTF8StringEncoding]];

    NSData *certificate = [self getFairPlayCertification:error];
    requestBytes = [loadingRequest streamingContentKeyRequestDataForApp:certificate
                                                      contentIdentifier:assetId
                                                                options:nil
                                                                  error:&error];

    NSData *responseData = nil;

    responseData = [self getContentKeyAndLeaseExpiryfromKeyServerModuleWithRequest:requestBytes
                                                             contentIdentifierHost:assetStr
                                                                             error:&error];

    if (responseData != nil)
    {
        [dataRequest respondWithData:responseData];

        [loadingRequest finishLoading];
    }
    else
    {
        [loadingRequest finishLoadingWithError:error];
    }

    handled = YES;

    return handled;
}

- (BOOL)resourceLoader:(AVAssetResourceLoader *)resourceLoader shouldWaitForRenewalOfRequestedResource:(AVAssetResourceRenewalRequest *)renewalRequest {
    return [self resourceLoader:resourceLoader shouldWaitForLoadingOfRequestedResource:renewalRequest];
}

@end
