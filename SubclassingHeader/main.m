//
//  main.m
//  SubclassingHeader
//
//  Created by James Sun on 24/11/2017.
//  Copyright © 2017 James Sun. All rights reserved.
//

#import <Foundation/Foundation.h>

@interface MethodResult : NSObject

@property BOOL isClassMethod;
@property (copy) NSString *propertyKey;
@property (copy) NSString *implementationString;

@end

@implementation MethodResult

- (NSString *)description {
    NSString *description = [super description];
    return [NSString stringWithFormat:@"%@, %@%@\n%@", description, self.isClassMethod ? @"+" : @"-", self.propertyKey, self.implementationString];
}

- (NSUInteger)hash {
    return @(self.isClassMethod).hash ^ (self.propertyKey ?: @"").hash;
}

- (BOOL)isEqual:(MethodResult *)object {
    if (![object isKindOfClass:[self class]]) {
        return NO;
    }

    if (self.isClassMethod != object.isClassMethod) {
        return NO;
    }

    if (![(self.propertyKey ?: @"") isEqualToString:(object.propertyKey ?: @"")]) {
        return NO;
    }

    return YES;
}

@end

NSDictionary *resultDictionary(NSString *string, NSTextCheckingResult *result) {
    NSMutableDictionary *resultDictionary = [NSMutableDictionary dictionary];
    for (NSInteger i = 0; i < result.numberOfRanges; i++) {
        NSRange range = [result rangeAtIndex:i];
        if (range.location != NSNotFound) {
            [resultDictionary setObject:[string substringWithRange:range] forKey:@(i)];
        }
    }
    return resultDictionary.copy;
}


NSString *capitalizedString(NSString *string) {
    NSString *capitalizedString = [[string substringToIndex:1].uppercaseString stringByAppendingString:[string substringFromIndex:1]];
    return capitalizedString;
}

NSString *trimmedString(NSString *string) {
    NSString *trimmedString = [string stringByTrimmingCharactersInSet:[NSCharacterSet whitespaceAndNewlineCharacterSet]];
    return trimmedString;
}

NSString *plainString(NSString *string) {
    NSString *plainString = [string stringByReplacingOccurrencesOfString:@"\r\n" withString:@" "];
    plainString = [string stringByReplacingOccurrencesOfString:@"\r" withString:@" "];
    plainString = [string stringByReplacingOccurrencesOfString:@"\n" withString:@" "];
    plainString = [plainString stringByReplacingOccurrencesOfString:@"\t" withString:@" "];
    while ([plainString rangeOfString:@"  "].location != NSNotFound) {
        plainString = [plainString stringByReplacingOccurrencesOfString:@"  " withString:@" "];
    }
    return plainString;
}

NSString *stringByRemoveSubstringsMatchingRegularExpression(NSString *string, NSString *regex) {
    NSRegularExpression *rex = [NSRegularExpression regularExpressionWithPattern:regex options:0 error:nil];
    NSArray *results = [rex matchesInString:string options:0 range:NSMakeRange(0, string.length)];
    results = [results sortedArrayUsingComparator:^NSComparisonResult(NSTextCheckingResult *result1, NSTextCheckingResult *result2) {
        return [@(result2.range.location) compare:@(result1.range.location)];
    }];
    NSString *resultString = string;
    for (NSTextCheckingResult *result in results) {
        resultString = [resultString stringByReplacingCharactersInRange:result.range withString:@""];
    }
    return resultString;
}

NSString *stringByRemovingObjCRuntime(NSString *string) {
// ([_]*[A-Z]{2,}_[A-Z_]+)\s*(\([^;]*\)|)
#define OBJC_RUNTIME_REGEX @"([_]*[A-Z]{2,}_[A-Z_]+)\\s*(\\([^;]*\\)|)"
    NSString *result = stringByRemoveSubstringsMatchingRegularExpression(string, OBJC_RUNTIME_REGEX);
// (?:\W)(IBOutlet|IBAction|IBOutletCollection\([\s\S]+?\))
#define OBJC_IB_REGEX @"(?:\\W)(IBOutlet|IBAction|IBOutletCollection\\([\\s\\S]+?\\))"
    result = stringByRemoveSubstringsMatchingRegularExpression(result, OBJC_IB_REGEX);
    return result;
}

void parsePointerPropertyNamePartString(NSString *string, NSString **namePointer, NSRange *rangePointer) {
    NSInteger location = [string rangeOfString:@"("].location;
    if (location == NSNotFound) {
        NSString *name = string;
        name = [name stringByReplacingOccurrencesOfString:@"const" withString:@""];
        name = [name stringByReplacingOccurrencesOfString:@"*" withString:@""];
        name = [name stringByReplacingOccurrencesOfString:@"^" withString:@""];
        name = trimmedString(name);
        if (namePointer) {
            *namePointer = name;
        }
        if (rangePointer) {
            NSRange range = [string rangeOfString:name];
            rangePointer->location = range.location;
            rangePointer->length = range.length;
        }
        return;
    }

    NSInteger embraces = 0;
    NSInteger begin = location;
    NSInteger length = 0;
    NSString *nameString = string;
    while (location < string.length) {
        NSString *charactor = [nameString substringWithRange:NSMakeRange(location, 1)];
        if ([charactor isEqualToString:@"("]) {
            embraces++;
        } else if ([charactor isEqualToString:@")"]) {
            embraces--;
            if (embraces == 0) {
                break;
            }
        } else {
            ;
        }
        length++;
        location++;
    }
    NSRange range = NSMakeRange(begin + 1, length - 1);
    NSString *name = [string substringWithRange:range];
    NSString *n = nil;
    NSRange r;
    parsePointerPropertyNamePartString(name, &n, &r);
    if (namePointer) {
        *namePointer = n;
    }
    range.location += r.location;
    range.length = r.length;

    if (rangePointer) {
        rangePointer->location = range.location;
        rangePointer->length = range.length;
    }
}

void parsePointerPropertyString(NSString *string, NSString **name, NSString **type) {
    NSRange range;
    NSString *nameString = nil;
    parsePointerPropertyNamePartString(string, &nameString, &range);
    if (name) {
        *name = nameString;
    }
    NSString *typeString = [string stringByReplacingCharactersInRange:range withString:@""];
    if (type) {
        *type = typeString;
    }
}

NSArray <MethodResult *>*methodResultsWithPropertyString(NSString *propertyString) {
// @property\s*(\((?<ATTRIBUTES>[\s\S]+?)\)|)(?<TYPEANDNAME>[\s\S]+?);
#define PROPERTY_PARSER_REGEX @"@property\\s*(\\((?<ATTRIBUTES>[\\s\\S]+?)\\)|)(?<TYPEANDNAME>[\\s\\S]+?);"
#define PROPERTY_PARSER_REGEX_NAMED_INDEX_ATTRIBUTES 2
#define PROPERTY_PARSER_REGEX_NAMED_INDEX_TYPEANDNAME 3
    NSRegularExpression *rex = [NSRegularExpression regularExpressionWithPattern:PROPERTY_PARSER_REGEX options:0 error:nil];
    NSArray *results = [rex matchesInString:propertyString options:0 range:NSMakeRange(0, propertyString.length)];
    NSTextCheckingResult *result = results.firstObject;
    NSString *attributesString = nil;
    NSString *typeNameString = nil;
    if (result == nil) {
        NSLog(@"Error: cannot parse property.");
        return nil;
    }

    NSDictionary *dictionary = resultDictionary(propertyString, result);
    attributesString = [dictionary objectForKey:@(PROPERTY_PARSER_REGEX_NAMED_INDEX_ATTRIBUTES)];
    typeNameString = [dictionary objectForKey:@(PROPERTY_PARSER_REGEX_NAMED_INDEX_TYPEANDNAME)];
    if (typeNameString.length == 0) {
        NSLog(@"Error: cannot parse property type and name.");
        return nil;
    }

    NSMutableArray *methodResults = [NSMutableArray array];
    BOOL isClassMethod = NO;
    NSString *propertyKey = nil;
    BOOL hasGetter = YES;
    BOOL hasSetter = YES;
    NSString *getterString = nil;
    NSString *setterString = nil;
    if (attributesString.length > 0) {
        NSArray *attributes = [[attributesString stringByReplacingOccurrencesOfString:@" " withString:@""] componentsSeparatedByString:@","];
        for (NSString *attribute in attributes) {
            if ([attribute isEqualToString:@"class"]) {
                isClassMethod = YES;
            }
            if ([attribute isEqualToString:@"readonly"]) {
                hasSetter = NO;
            }
            if ([attribute hasPrefix:@"getter="]) {
                getterString = [attribute substringFromIndex:@"getter=".length];
            }
            if ([attribute isEqualToString:@"setter="]) {
                setterString = [attribute substringFromIndex:@"setter=".length];
            }
        }
    }

    typeNameString = trimmedString(typeNameString);
    NSString *typeString = nil;
    NSString *nameString = nil;
    if (![typeNameString hasSuffix:@")"]) {
// (?<TYPE>[\s\S]*)(?<NAME>\w+)$
#define PROPERTY_TYPE_NAME_PARSER_REGEX @"(?<TYPE>[\\s\\S]*?)(?<NAME>\\w+)$"
#define PROPERTY_TYPE_NAME_PARSER_REGEX_NAMED_INDEX_TYPE 1
#define PROPERTY_TYPE_NAME_PARSER_REGEX_NAMED_INDEX_NAME 2
        NSRegularExpression *rex = [NSRegularExpression regularExpressionWithPattern:PROPERTY_TYPE_NAME_PARSER_REGEX options:0 error:nil];
        NSArray *results = [rex matchesInString:typeNameString options:0 range:NSMakeRange(0, typeNameString.length)];
        NSTextCheckingResult *result = results.firstObject;
        NSDictionary *dictionary = resultDictionary(typeNameString, result);
        typeString = [dictionary objectForKey:@(PROPERTY_TYPE_NAME_PARSER_REGEX_NAMED_INDEX_TYPE)];
        typeString = trimmedString(typeString);
        nameString = [dictionary objectForKey:@(PROPERTY_TYPE_NAME_PARSER_REGEX_NAMED_INDEX_NAME)];

        if (hasGetter) {
            if (getterString == nil) {
                getterString = nameString;
            }
            propertyKey = getterString;

            NSMutableString *implementationString = [NSMutableString string];
            [implementationString appendFormat:@"%@ (%@)%@ {\n", isClassMethod ? @"+" : @"-", typeString, getterString];
            [implementationString appendFormat:@"    return [super %@];\n}", getterString];

            MethodResult *methodResult = [[MethodResult alloc] init];
            methodResult.isClassMethod = isClassMethod;
            methodResult.propertyKey = propertyKey;
            methodResult.implementationString = implementationString;
            [methodResults addObject:methodResult];
        }

        if (hasSetter) {
            if (setterString == nil) {
                setterString = [NSString stringWithFormat:@"set%@", capitalizedString(nameString)];
            }
            propertyKey = [setterString stringByAppendingString:@":"];

            NSMutableString *implementationString = [NSMutableString string];
            [implementationString appendFormat:@"%@ (void)%@:(%@)%@ {\n", isClassMethod ? @"+" : @"-", setterString, typeString, nameString];
            [implementationString appendFormat:@"    [super %@:%@];\n}", setterString, nameString];


            MethodResult *methodResult = [[MethodResult alloc] init];
            methodResult.isClassMethod = isClassMethod;
            methodResult.propertyKey = propertyKey;
            methodResult.implementationString = implementationString;
            [methodResults addObject:methodResult];
        }
    } else {
        parsePointerPropertyString(typeNameString, &nameString, &typeString);
        if (hasGetter) {
            if (getterString == nil) {
                getterString = nameString;
            }
            propertyKey = getterString;

            NSMutableString *implementationString = [NSMutableString string];
            [implementationString appendFormat:@"%@ (%@)%@ {\n", isClassMethod ? @"+" : @"-", typeString, getterString];
            [implementationString appendFormat:@"    return [super %@];\n}", getterString];

            MethodResult *methodResult = [[MethodResult alloc] init];
            methodResult.isClassMethod = isClassMethod;
            methodResult.propertyKey = propertyKey;
            methodResult.implementationString = implementationString;
            [methodResults addObject:methodResult];
        }

        if (hasSetter) {
            if (setterString == nil) {
                setterString = [NSString stringWithFormat:@"set%@", capitalizedString(nameString)];
            }
            propertyKey = [setterString stringByAppendingString:@":"];

            NSMutableString *implementationString = [NSMutableString string];
            [implementationString appendFormat:@"%@ (void)%@:(%@)%@ {\n", isClassMethod ? @"+" : @"-", setterString, typeString, nameString];
            [implementationString appendFormat:@"    [super %@:%@];\n}", setterString, nameString];


            MethodResult *methodResult = [[MethodResult alloc] init];
            methodResult.isClassMethod = isClassMethod;
            methodResult.propertyKey = propertyKey;
            methodResult.implementationString = implementationString;
            [methodResults addObject:methodResult];
        }
    }

    return methodResults.copy;
}

MethodResult *methodResultWithMethodString(NSString *methodString) {
// [-+]\s*\((?<RETURNTYPENAME>[^:]+)\)\s*(?<MAINPARTNAME>\w+\s*|(\w+\s*:\s*\([^:]+\)\s*\w+\s*)*);
#define METHOD_PARSER_REGEX @"[-+]\\s*\\((?<RETURNTYPENAME>[^:]+)\\)\\s*(?<MAINPARTNAME>\\w+\\s*|(\\w+\\s*:\\s*\\([^:]+\\)\\s*\\w+\\s*)*);"
#define METHOD_PARSER_REGEX_NAMED_INDEX_RETURN_TYPE 1
#define METHOD_PARSER_REGEX_NAMED_INDEX_MAIN_PART 2
    BOOL isClassMethod = [methodString hasPrefix:@"+"];
    NSString *propertyKey = methodString;
    NSMutableString *implementationString = [NSMutableString string];
    NSRegularExpression *rex = [NSRegularExpression regularExpressionWithPattern:METHOD_PARSER_REGEX options:0 error:nil];
    NSArray *results = [rex matchesInString:methodString options:0 range:NSMakeRange(0, methodString.length)];
    NSTextCheckingResult *result = results.firstObject;
    if (result) {
        NSDictionary *dictionary = resultDictionary(methodString, result);
        NSString *returnType = trimmedString([dictionary objectForKey:@(METHOD_PARSER_REGEX_NAMED_INDEX_RETURN_TYPE)]);
        NSString *mainPart = trimmedString([dictionary objectForKey:@(METHOD_PARSER_REGEX_NAMED_INDEX_MAIN_PART)]);
// \([^:]*\)
#define EMBRACES_IN_METHOD_REGEX @"\\([^:]*\\)"
        NSString *mainPartCall = stringByRemoveSubstringsMatchingRegularExpression(mainPart, EMBRACES_IN_METHOD_REGEX);
// (?:\s*:)\s*\w+
#define ARGUMENTS_IN_METHOD_REGEX @"(?:\\s*:)\\s*\\w+"
        propertyKey = stringByRemoveSubstringsMatchingRegularExpression(mainPartCall, ARGUMENTS_IN_METHOD_REGEX);
        propertyKey = [propertyKey stringByReplacingOccurrencesOfString:@" " withString:@""];
        BOOL isVoid = [returnType isEqualToString:@"void"];
        NSString *firstLine = [methodString substringToIndex:methodString.length - 1];
        firstLine = trimmedString(firstLine);
        [implementationString appendString:firstLine];
        [implementationString appendFormat:@" {\n    "];
        if (!isVoid) {
            [implementationString appendString:@"return "];
        }
        [implementationString appendFormat:@"[super %@];\n}", mainPartCall];
    } else {
        [implementationString appendFormat:@"#warning\n//%@", methodString];
    }

    MethodResult *methodResult = [[MethodResult alloc] init];
    methodResult.isClassMethod = isClassMethod;
    methodResult.propertyKey = propertyKey;
    methodResult.implementationString = implementationString;
    return methodResult;
}

NSArray <MethodResult *>*methodResultsWithPropertyOrMethodString(NSString *propertyOrMethodString) {
    if ([propertyOrMethodString hasPrefix:@"@property"]) {
        return methodResultsWithPropertyString(propertyOrMethodString);
    } else {
        MethodResult *result = methodResultWithMethodString(propertyOrMethodString);
        return result ? @[result] : nil;
    }
}

NSString *methodsStringWithHeaderClassString(NSString *headerClassString) {
// @property[^?]+?;
#define PROPERTY_REGEX @"@property[^;]+?;"
// [-+]\s*\([^;]+?;
#define METHOD_REGEX @"[-+]\\s*\\([^;]+?;"
#define PROPERTY_METHOD_REGEX PROPERTY_REGEX @"|" METHOD_REGEX
    NSRegularExpression *rex = [NSRegularExpression regularExpressionWithPattern:PROPERTY_METHOD_REGEX options:0 error:nil];
    NSArray *results = [rex matchesInString:headerClassString options:0 range:NSMakeRange(0, headerClassString.length)];
    NSMutableArray *methods = [NSMutableArray array];
    for (NSTextCheckingResult *result in results) {
        NSString *propertyOrMethodString = [headerClassString substringWithRange:result.range];
        propertyOrMethodString = plainString(propertyOrMethodString);
        propertyOrMethodString = stringByRemovingObjCRuntime(propertyOrMethodString);
        NSArray <MethodResult *> *methodResults = methodResultsWithPropertyOrMethodString(propertyOrMethodString);
        for (MethodResult *each in methodResults) {
            if (![methods containsObject:each]) {
                [methods addObject:each];
            }
        }
    }
    NSMutableString *methodsString = [NSMutableString string];
    for (NSInteger i = 0; i < methods.count; i++) {
        if (i != 0) {
            [methodsString appendString:@"\n"];
            [methodsString appendString:@"\n"];
        }
        MethodResult *method = [methods objectAtIndex:i];
        [methodsString appendString:method.implementationString];
    }
    return methodsString.copy;
}

void parseHeaderClassString(NSString *headerClassString, NSString **classString, NSString **superclassString, NSString **categoryString) {
// @interface\s+(?<CLASSNAME>\w+)\s*(:\s*(?<SUPERCLASSNAME>\w+)|\(\s*(?<CATOGORYNAME>\w+)\s*\)|\s)"
#define INTERFACE_REGEX @"@interface\\s+(?<CLASSNAME>\\w+)\\s*(:\\s*(?<SUPERCLASSNAME>\\w+)|\\(\\s*(?<CATOGORYNAME>\\w+)\\s*\\)|\\s)"
#define INTERFACE_REGEX_NAMED_INDEX_CLASSNAME 1
#define INTERFACE_REGEX_NAMED_INDEX_SUPERCLASSNAME 3
#define INTERFACE_REGEX_NAMED_INDEX_CATOGORYNAME 4
    NSRegularExpression *rex = [NSRegularExpression regularExpressionWithPattern:INTERFACE_REGEX options:0 error:nil];
    NSArray *results = [rex matchesInString:headerClassString options:0 range:NSMakeRange(0, headerClassString.length)];
    NSTextCheckingResult *result = results.firstObject;
    NSString *resultClassString = nil;
    NSString *resultSuperclassString = nil;
    NSString *resultCategoryString = nil;
    if (result == nil) {
        NSLog(@"Error: cannot parse class.");
        return;
    }

    NSDictionary *dictionary = resultDictionary(headerClassString, result);
    resultClassString = [dictionary objectForKey:@(INTERFACE_REGEX_NAMED_INDEX_CLASSNAME)];
    resultSuperclassString = [dictionary objectForKey:@(INTERFACE_REGEX_NAMED_INDEX_SUPERCLASSNAME)];
    resultCategoryString = [dictionary objectForKey:@(INTERFACE_REGEX_NAMED_INDEX_CATOGORYNAME)];

    if (classString) {
        *classString = resultClassString;
    }
    if (superclassString) {
        *superclassString = resultSuperclassString;
    }
    if (categoryString) {
        *categoryString = resultCategoryString;
    }
}

NSString *subclassingContentStringWithHeaderClassString(NSString *headerClassString) {
    NSString *className = nil;
    NSString *superclassName = nil;
    NSString *categoryString = nil;
    parseHeaderClassString(headerClassString, &className, &superclassName, &categoryString);
    NSMutableString *subclassingContentString = [NSMutableString string];
    if (className) {
        NSString *subclassName = [NSString stringWithFormat:@"S%@", className];
        [subclassingContentString appendFormat:@"@implementation %@", subclassName];
        if (categoryString) {
            [subclassingContentString appendFormat:@" (%@)", categoryString];
        }
        [subclassingContentString appendString:@"\n\n"];

        NSString *methodsString = methodsStringWithHeaderClassString(headerClassString);
        if (methodsString.length > 0) {
            [subclassingContentString appendString:methodsString];
            [subclassingContentString appendString:@"\n\n"];
        }

        [subclassingContentString appendString:@"@end\n\n"];
    }
    return subclassingContentString.copy;
};

NSString *stringByRemovingComment(NSString *string) {
    NSString *blockComments = @"/[*](.*?)[*]/";
    NSString *lineComments = @"//(.*?)\r?\n";
    NSString *strings = @"\"((\\[^\n]|[^""\n])*)\"";
    NSString *verbatimStrings = @"@(\"[^\"]*\")+";
    NSMutableArray *removes = [NSMutableArray array];

    NSString *text = string;
    NSRegularExpression *regexComments = [NSRegularExpression regularExpressionWithPattern:[NSString stringWithFormat:@"%@|%@|%@|%@", blockComments, lineComments, strings, verbatimStrings] options:NSRegularExpressionCaseInsensitive | NSRegularExpressionDotMatchesLineSeparators error:NULL];

    NSArray* matches = [regexComments matchesInString:text options:0 range:NSMakeRange(0, text.length)];
    for (NSTextCheckingResult *match in matches) {
        NSString *outer = [text substringWithRange:match.range];
        if ([outer hasPrefix:@"/*"] || [outer hasPrefix:@"//"]){
            [removes addObject:outer];
        }
    }

    for (NSString *match in [removes valueForKeyPath:@"@distinctUnionOfObjects.self"]){
        text = [text stringByReplacingOccurrencesOfString:match withString:@""];
    }

    return text;
}

NSString *subclassingContentStringWithHeaderString(NSString *headerString) {
    NSMutableString *subclassingContentString = [NSMutableString string];

    NSString *string = stringByRemovingComment(headerString);
    while (YES) {
        NSRange interfaceStringRange = [string rangeOfString:@"@interface"];
        if (interfaceStringRange.location == NSNotFound) {
            break;
        }
        NSString *interfacePrefixString = [string substringFromIndex:interfaceStringRange.location];
        NSRange endStringRange = [interfacePrefixString rangeOfString:@"@end"];
        if (endStringRange.location == NSNotFound) {
            NSLog(@"Error:%@", @"@end not found to match @interface!");
            break;
        }
        NSString *classString = [string substringWithRange:NSMakeRange(interfaceStringRange.location, endStringRange.location + endStringRange.length)];
        string = [string substringFromIndex:interfaceStringRange.location + endStringRange.location + endStringRange.length];

        NSString *subclassString = subclassingContentStringWithHeaderClassString(classString);
        [subclassingContentString appendString:subclassString];
    }

    return subclassingContentString.copy;
}

int main(int argc, const char * argv[]) {
    @autoreleasepool {
        if (argc <= 1) {
            NSLog(@"no input file");
            return 0;
        }
        const char *self = argv[0];
        const char *file = argv[1];
        if (file == nil) {
            NSLog(@"Error:no input file");
            return -1;
        }
        NSError *error = nil;
        NSString *selfFile = @(self);
        NSString *headerFile = @(file);
        NSString *outputFile = [[[[selfFile stringByDeletingLastPathComponent] stringByAppendingPathComponent:[@"S" stringByAppendingString:headerFile.lastPathComponent]] stringByDeletingPathExtension] stringByAppendingPathExtension:@"m"];
        NSString *headerString = [NSString stringWithContentsOfFile:headerFile encoding:NSUTF8StringEncoding error:&error];
        if (error != nil) {
            NSLog(@"Error:%@", error.description);
            return -1;
        }
        NSString *subclassingContentString = subclassingContentStringWithHeaderString(headerString);
        [subclassingContentString writeToFile:outputFile atomically:YES encoding:NSUTF8StringEncoding error:&error];
        if (error != nil) {
            NSLog(@"Error:%@", error.description);
            return -1;
        }
    }
    return 0;
}
