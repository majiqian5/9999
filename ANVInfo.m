#import "ANVInfo.h"

static NSArray<NSString *> *ANVLunarMonthNames(void) {
    return @[@"正月", @"二月", @"三月", @"四月", @"五月", @"六月",
             @"七月", @"八月", @"九月", @"十月", @"冬月", @"腊月"];
}

static NSString *ANVLunarDayName(NSInteger day) {
    if (day <= 0) return @"";
    NSArray *digits = @[@"", @"一", @"二", @"三", @"四", @"五", @"六", @"七", @"八", @"九", @"十"];
    if (day <= 10) return [@"初" stringByAppendingString:digits[day]];
    if (day < 20) return [@"十" stringByAppendingString:digits[day - 10]];
    if (day == 20) return @"二十";
    if (day < 30) return [@"廿" stringByAppendingString:digits[day - 20]];
    return @"三十";
}

/// 二十四节气（21 世纪近似公式：day = [Y*0.2422 + C] - [Y/4]，Y 为年份后两位）
static NSArray<NSString *> *ANVSolarTermNames(void) {
    return @[@"小寒", @"大寒", @"立春", @"雨水", @"惊蛰", @"春分",
             @"清明", @"谷雨", @"立夏", @"小满", @"芒种", @"夏至",
             @"小暑", @"大暑", @"立秋", @"处暑", @"白露", @"秋分",
             @"寒露", @"霜降", @"立冬", @"小雪", @"大雪", @"冬至"];
}

static NSInteger ANVSolarTermDay(NSInteger year, NSInteger idx) {
    static CGFloat const c[24] = {
        5.4055, 20.12, 3.87, 18.73, 5.63, 20.646,
        4.81, 20.1, 5.52, 21.04, 5.678, 21.37,
        7.108, 22.83, 7.5, 23.13, 7.646, 23.042,
        8.318, 23.438, 7.438, 22.36, 7.18, 21.94
    };
    NSInteger y = year % 100;
    CGFloat base = (CGFloat)y * 0.2422 + c[idx];
    NSInteger day = (NSInteger)floor(base) - (NSInteger)floor((CGFloat)(y - 1) / 4.0);
    return day;
}

@implementation ANVInfo

static NSCalendar *ANVChineseCalendar(void) {
    static NSCalendar *cal;
    static dispatch_once_t once;
    dispatch_once(&once, ^{
        cal = [[NSCalendar alloc] initWithCalendarIdentifier:NSCalendarIdentifierChinese];
    });
    return cal;
}

static NSCalendar *ANVGregorian(void) {
    static NSCalendar *cal;
    static dispatch_once_t once;
    dispatch_once(&once, ^{
        cal = [[NSCalendar alloc] initWithCalendarIdentifier:NSCalendarIdentifierGregorian];
    });
    return cal;
}

+ (NSString *)lunarLine {
    NSCalendar *cal = ANVChineseCalendar();
    NSCalendarUnit units = NSCalendarUnitMonth | NSCalendarUnitDay;
    NSDateComponents *c = [cal components:units fromDate:[NSDate date]];
    NSInteger m = c.month;
    if (m < 1 || m > 12) return nil;
    NSString *mn = ANVLunarMonthNames()[m - 1];
    NSString *dn = ANVLunarDayName(c.day);
    return [NSString stringWithFormat:@"农历%@%@", mn, dn];
}

+ (NSString *)timeLine {
    NSDateFormatter *fmt = [[NSDateFormatter alloc] init];
    fmt.locale = [NSLocale localeWithLocaleIdentifier:@"zh_CN"];
    fmt.dateFormat = @"EEE HH:mm";
    return [fmt stringFromDate:[NSDate date]];
}

/// 固定公历节日
static NSDictionary *ANVSolarFestivals(void) {
    return @{@"1-1": @"元旦", @"2-14": @"情人节", @"3-8": @"妇女节",
             @"5-1": @"劳动节", @"6-1": @"儿童节", @"10-1": @"国庆节",
             @"12-25": @"圣诞节"};
}

/// 农历节日（月-日）
static NSDictionary *ANVLunarFestivals(void) {
    return @{@"1-1": @"春节", @"1-15": @"元宵", @"2-2": @"龙抬头",
             @"5-5": @"端午", @"7-7": @"七夕", @"7-15": @"中元",
             @"8-15": @"中秋", @"9-9": @"重阳", @"12-8": @"腊八", @"12-23": @"小年"};
}

+ (NSString *)festivalLine {
    static NSString *cache = nil;
    static NSInteger cacheDay = -1;
    NSDate *nowDate = [NSDate date];
    NSInteger dayStamp = (NSInteger)floor([nowDate timeIntervalSince1970] / 86400.0);
    if (cache && cacheDay == dayStamp) return cache;

    NSCalendar *greg = ANVGregorian();
    NSCalendar *chinese = ANVChineseCalendar();
    NSDate *today = [greg startOfDayForDate:[NSDate date]];
    NSDictionary *solar = ANVSolarFestivals();
    NSDictionary *lunar = ANVLunarFestivals();
    NSArray *termNames = ANVSolarTermNames();

    NSString *bestName = nil;
    NSInteger bestDays = 9999;

    for (NSInteger offset = 0; offset <= 400; offset++) {
        NSDate *day = [today dateByAddingTimeInterval:(NSTimeInterval)offset * 86400.0];
        NSDateComponents *g = [greg components:(NSCalendarUnitYear | NSCalendarUnitMonth | NSCalendarUnitDay)
                                      fromDate:day];
        NSString *key = [NSString stringWithFormat:@"%ld-%ld", (long)g.month, (long)g.day];
        NSString *name = solar[key];

        NSDateComponents *lc = [chinese components:(NSCalendarUnitMonth | NSCalendarUnitDay)
                                          fromDate:day];
        NSString *lkey = [NSString stringWithFormat:@"%ld-%ld", (long)lc.month, (long)lc.day];
        if (!name) name = lunar[lkey];

        if (!name) {
            for (NSInteger i = 0; i < 24; i++) {
                NSInteger termDay = ANVSolarTermDay(g.year, i);
                NSInteger termMonth = i / 2 + 1;
                if (termMonth == g.month && termDay == g.day) {
                    name = termNames[i];
                    break;
                }
            }
        }

        if (name) {
            bestName = name;
            bestDays = offset;
            break;
        }
    }

    if (!bestName) return nil;
    cacheDay = dayStamp;
    if (bestDays == 0) cache = [NSString stringWithFormat:@"%@ · 今天", bestName];
    else if (bestDays == 1) cache = [NSString stringWithFormat:@"%@ · 明天", bestName];
    else cache = [NSString stringWithFormat:@"%@ · 还有%ld天", bestName, (long)bestDays];
    return cache;
}

+ (NSString *)weatherLineFrom:(NSDictionary *)weather {
    if (!weather) return nil;
    if ([weather isKindOfClass:[NSString class]]) {
        NSString *w = (NSString *)weather;
        return w.length ? w : nil;
    }
    if (![weather isKindOfClass:[NSDictionary class]]) return nil;

    NSDictionary *d = weather;
    NSString *text = nil;
    for (NSString *k in @[@"text", @"condition", @"desc", @"weather", @"summary"]) {
        id v = d[k];
        if ([v isKindOfClass:[NSString class]] && [v length]) { text = v; break; }
    }
    NSString *temp = nil;
    for (NSString *k in @[@"temp", @"temperature", @"tempNow", @"now"]) {
        id v = d[k];
        if ([v isKindOfClass:[NSString class]] && [v length]) { temp = v; break; }
        if ([v isKindOfClass:[NSNumber class]]) { temp = [v stringValue]; break; }
    }
    NSString *high = nil, *low = nil;
    for (NSString *k in @[@"high", @"tempHigh", @"highTemp"]) {
        id v = d[k];
        if ([v isKindOfClass:[NSString class]] || [v isKindOfClass:[NSNumber class]]) { high = [v description]; break; }
    }
    for (NSString *k in @[@"low", @"tempLow", @"lowTemp"]) {
        id v = d[k];
        if ([v isKindOfClass:[NSString class]] || [v isKindOfClass:[NSNumber class]]) { low = [v description]; break; }
    }

    NSMutableArray *parts = [NSMutableArray array];
    if (text.length) [parts addObject:text];
    if (temp.length) {
        NSString *t = [temp containsString:@"°"] ? temp : [temp stringByAppendingString:@"°"];
        [parts addObject:t];
    } else if (high.length && low.length) {
        [parts addObject:[NSString stringWithFormat:@"%@/%@°", low, high]];
    }
    if (!parts.count) return nil;
    return [parts componentsJoinedByString:@" "];
}

+ (NSString *)nextInfoLineWithWeather:(NSDictionary *)weather {
    static NSInteger cursor = 0;
    NSMutableArray<NSString *> *items = [NSMutableArray array];
    NSString *w = [self weatherLineFrom:weather];
    if (w.length) [items addObject:w];
    NSString *l = [self lunarLine];
    if (l.length) [items addObject:l];
    NSString *f = [self festivalLine];
    if (f.length) [items addObject:f];
    NSString *t = [self timeLine];
    if (t.length) [items addObject:t];
    if (!items.count) return nil;

    cursor = (cursor + 1) % (NSInteger)items.count;
    return items[(NSUInteger)cursor];
}

@end
