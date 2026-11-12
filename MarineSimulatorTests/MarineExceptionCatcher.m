#import <Foundation/Foundation.h>

static NSException *MarineLastCaughtException = nil;

NSException * _Nullable MarineCatchException(void (^ _Nonnull block)(void)) {
    MarineLastCaughtException = nil;
    @try {
        block();
    } @catch (NSException *exception) {
        MarineLastCaughtException = exception;
    }
    return MarineLastCaughtException;
}
