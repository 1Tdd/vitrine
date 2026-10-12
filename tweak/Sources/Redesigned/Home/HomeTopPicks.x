// Home redesign: Top picks, the first shelf of cards drawn large the way the Music app draws its top shelf:
// each card the cover edge to edge over a footer in the cover's color, 60% of the page wide so the next one
// shows at the trailing edge.
//
// A shelf is a Home_CarouselKit.TouchCancellingCollectionView in a cell of the page's list (HomeSections.x), a
// compositional layout of its own with cards under a 40pt heading (9.1.78: cards 149 by 195, a square picture
// over 46pt of text; 9.1.90's Recents: 98 by 144, the picture 94 at 2pt in, over 38pt of text). Its sizes are
// Spotify's, made by the layout's section provider each time the layout is asked for one. So every
// compositional layout's provider is wrapped, and while the large shelf's provider runs, a size kSmallest or
// more wide is made as many times wider as the card needs to reach kCardShare of the page, and taller by what
// the card grows: the card to its new width plus kFooter, the row that holds the cards by the same amount.
// The page's cell is made taller by the same amount.
//
// The shelf drawn large is the one nearest the top of the page: the lowest index any shelf has been measured at.
// Cells are reused across shelves, so each measuring sets or clears the mark on the layout it holds.
//
// A large card (SGRHomeStyleLargeCard, from HomeCards.x on every layout of the card) keeps Spotify's button, cover
// and touch. A surface in the cover's color (SGRHomeTintForCover) goes behind everything, the cover's top corners
// take the card's radius, and two labels of the Kit's own stand in the footer over Spotify's, which go
// transparent: the leading one bold with what Spotify says under the title ("Album • Artist", or the makers of a
// mix), the other the title in the secondary color, which is how the reference lays its footer out. A card with
// no second line leads with its title.
#import <objc/runtime.h>
#import "Core/SGCore.h"
#import "Settings/SGModPage.h"
#import "Redesigned/Kit/SGRKit.h"
#import "Home.h"

static const CGFloat kCardShare = 0.6, kFooter = 76, kSmallest = 80, kHeading = 40;
// A card this wide or wider is one drawn large: Spotify's widest is 153.
static const CGFloat kLargeCard = 200;
static const CGFloat kFooterTop = 12, kFooterGap = 2;
// How far under the page's title the large shelf's cards sit, once its heading has gone.
// The reference's cards start 2pt above the feed's top (110pt on a 393pt phone against the feed's 112).
static const CGFloat kBandAbove = -2;
// The footer's text, in from the card's edges (the reference's first glyph sits 13.7pt in; a glyph's side bearing
// is about 1.5).
static const CGFloat kFooterInset = 12;
static char kLargeKey, kNaturalKey, kWrappedKey, kGrowKey, kAskedKey, kListKey, kOffsetKey, kHeldKey, kShowAllKey, kHeadingKey;
static __weak UICollectionView *sg_largeShelf;
static _Thread_local BOOL sg_enlarging;
// The list section the shortcuts grid is in, from its measuring; NSNotFound until one is.
static NSInteger sg_gridSection = NSNotFound;
static _Thread_local CGFloat sg_containerWidth;
// Spotify's card in the running provider: the narrowest size kSmallest or more wide, and how much taller the
// large one is than it. 0 until a card is made.
static _Thread_local CGFloat sg_cardWidth, sg_cardGrow;
static NSInteger sg_topIndex = NSIntegerMax;

// The layout a wrapped provider belongs to, set once the layout is made.
@interface SGRLayoutBox : NSObject
@property (nonatomic, weak) UICollectionViewCompositionalLayout *layout;
@end
@implementation SGRLayoutBox
@end

static CGFloat targetWidth(void) {
    return round(sg_containerWidth * kCardShare);
}

static UICollectionViewCompositionalLayoutSectionProvider wrapped(UICollectionViewCompositionalLayoutSectionProvider provider, SGRLayoutBox *box) {
    return ^NSCollectionLayoutSection *(NSInteger section, id<NSCollectionLayoutEnvironment> environment) {
        UICollectionViewCompositionalLayout *layout = box.layout;
        BOOL was = sg_enlarging;
        CGFloat wasWidth = sg_cardWidth, wasGrow = sg_cardGrow, wasContainer = sg_containerWidth;
        sg_enlarging = layout && objc_getAssociatedObject(layout, &kLargeKey) != nil;
        sg_containerWidth = environment.container.effectiveContentSize.width;
        sg_cardWidth = sg_cardGrow = 0;
        NSCollectionLayoutSection *made = provider(section, environment);
        if (layout && sg_cardGrow > 0) objc_setAssociatedObject(layout, &kGrowKey, @(sg_cardGrow), OBJC_ASSOCIATION_RETAIN_NONATOMIC);
        sg_enlarging = was;
        sg_cardWidth = wasWidth;
        sg_cardGrow = wasGrow;
        sg_containerWidth = wasContainer;
        return made;
    };
}

static UICollectionViewCompositionalLayout *boxed(UICollectionViewCompositionalLayout *made, SGRLayoutBox *box) {
    box.layout = made;
    if (made) objc_setAssociatedObject(made, &kWrappedKey, @YES, OBJC_ASSOCIATION_RETAIN_NONATOMIC);
    return made;
}

#pragma mark - the shelf above the grid

// Spotify's feed puts the shortcuts grid first and the shelves after it; the reference puts the large shelf first,
// right under the title, and the grid under it. The list's layout is Spotify's, one cell per section, so its
// attributes are moved as the list asks for them: the shelf's block takes the grid's place and the grid's moves
// down by the shelf's height, the gap between them kept. The sections between (dropped, 0 tall) stay where they
// are. Nothing else about the layout changes: its content size and every other section's place are its own.
static _Thread_local BOOL sg_unmoved;   // reading the layout's own frames, not the moved ones

// The grid's and the shelf's frames as the layout has them, and where the sections before the shelf end (the
// grid's bottom, or a kept shelf's when Cards from names a later one); NO while there is no swap to make.
static BOOL blocks(UICollectionViewLayout *layout, CGRect *grid, CGRect *shelf, CGFloat *before) {
    NSInteger shelfSection = sg_topIndex == NSIntegerMax ? NSNotFound : sg_topIndex / 10000;
    if (sg_gridSection == NSNotFound || shelfSection == NSNotFound || sg_gridSection >= shelfSection) return NO;
    if (!objc_getAssociatedObject(layout, &kListKey)) return NO;
    sg_unmoved = YES;
    UICollectionViewLayoutAttributes *a = [layout layoutAttributesForItemAtIndexPath:[NSIndexPath indexPathForItem:0 inSection:sg_gridSection]];
    UICollectionViewLayoutAttributes *b = [layout layoutAttributesForItemAtIndexPath:[NSIndexPath indexPathForItem:sg_topIndex % 10000 inSection:shelfSection]];
    CGFloat last = CGRectGetMaxY(a.frame);
    if (a && b) {
        for (UICollectionViewLayoutAttributes *between in [layout layoutAttributesForElementsInRect:CGRectUnion(a.frame, b.frame)]) {
            NSInteger section = between.indexPath.section;
            if (section >= sg_gridSection && section < shelfSection) last = MAX(last, CGRectGetMaxY(between.frame));
        }
    }
    sg_unmoved = NO;
    if (!a || !b || last > CGRectGetMinY(b.frame)) return NO;
    *grid = a.frame;
    *shelf = b.frame;
    *before = last;
    return YES;
}

// The shelf's block takes the grid's place; the grid and everything between it and the shelf move down by the
// shelf's block, the gap above the shelf (its section inset) kept between the two.
static void move(UICollectionViewLayoutAttributes *attributes, CGRect grid, CGRect shelf, CGFloat before) {
    NSInteger section = attributes.indexPath.section, shelfSection = sg_topIndex / 10000;
    CGRect frame = attributes.frame;
    if (section >= sg_gridSection && section < shelfSection) frame.origin.y += CGRectGetMaxY(shelf) - before;
    else if (section == shelfSection) frame.origin.y += CGRectGetMinY(grid) - CGRectGetMinY(shelf);
    else return;
    attributes.frame = frame;
}

// The large shelf's heading, scrolled out of its bounds, would be recycled by the shelf, and with it the Show all
// the header's menu offers: its attributes stay in what the layout answers, so the shelf keeps the view (clipped,
// and transparent). Which supplementary it is, the layout said itself while the heading was in view.
static char kHeadingKindKey, kHeadingPathKey;
static NSArray<UICollectionViewLayoutAttributes *> *keptHeading(UICollectionViewLayout *layout, NSArray<UICollectionViewLayoutAttributes *> *made) {
    NSString *kind = objc_getAssociatedObject(layout, &kHeadingKindKey);
    NSIndexPath *path = objc_getAssociatedObject(layout, &kHeadingPathKey);
    for (UICollectionViewLayoutAttributes *attributes in made) {
        if (attributes.representedElementCategory != UICollectionElementCategorySupplementaryView) continue;
        if (!kind) {
            objc_setAssociatedObject(layout, &kHeadingKindKey, attributes.representedElementKind, OBJC_ASSOCIATION_COPY_NONATOMIC);
            objc_setAssociatedObject(layout, &kHeadingPathKey, attributes.indexPath, OBJC_ASSOCIATION_COPY_NONATOMIC);
        }
        return made;
    }
    if (!kind || !path) return made;
    UICollectionViewLayoutAttributes *heading = [layout layoutAttributesForSupplementaryViewOfKind:kind atIndexPath:path];
    return heading ? [made arrayByAddingObject:heading] : made;
}

%hook UICollectionViewCompositionalLayout
- (instancetype)initWithSectionProvider:(UICollectionViewCompositionalLayoutSectionProvider)provider
                          configuration:(UICollectionViewCompositionalLayoutConfiguration *)configuration {
    if (!provider) return %orig;
    SGRLayoutBox *box = [SGRLayoutBox new];
    return boxed(%orig(wrapped(provider, box), configuration), box);
}
- (instancetype)initWithSectionProvider:(UICollectionViewCompositionalLayoutSectionProvider)provider {
    if (!provider) return %orig;
    SGRLayoutBox *box = [SGRLayoutBox new];
    return boxed(%orig(wrapped(provider, box)), box);
}
- (NSArray<UICollectionViewLayoutAttributes *> *)layoutAttributesForElementsInRect:(CGRect)rect {
    CGRect grid, shelf;
    CGFloat before;
    if (objc_getAssociatedObject(self, &kLargeKey)) {
        NSArray<UICollectionViewLayoutAttributes *> *made = %orig;
        return keptHeading((UICollectionViewLayout *)self, made);
    }
    if (sg_unmoved || !blocks((UICollectionViewLayout *)self, &grid, &shelf, &before)) return %orig;
    // Everything between the two blocks moves within their band, so the band is asked for whole.
    CGRect band = CGRectUnion(grid, shelf);
    if (!CGRectIntersectsRect(rect, band)) return %orig;
    NSMutableArray<UICollectionViewLayoutAttributes *> *moved = [NSMutableArray array];
    CGRect whole = CGRectUnion(rect, band);
    NSArray<UICollectionViewLayoutAttributes *> *all = %orig(whole);
    for (UICollectionViewLayoutAttributes *attributes in all) {
        UICollectionViewLayoutAttributes *copy = [attributes copy];
        move(copy, grid, shelf, before);
        if (CGRectIntersectsRect(copy.frame, rect)) [moved addObject:copy];
    }
    return moved;
}

- (UICollectionViewLayoutAttributes *)layoutAttributesForItemAtIndexPath:(NSIndexPath *)indexPath {
    UICollectionViewLayoutAttributes *attributes = %orig;
    CGRect grid, shelf;
    CGFloat before;
    if (sg_unmoved || !attributes || !blocks((UICollectionViewLayout *)self, &grid, &shelf, &before)) return attributes;
    UICollectionViewLayoutAttributes *copy = [attributes copy];
    move(copy, grid, shelf, before);
    return copy;
}
%end

%hook NSCollectionLayoutSize
+ (instancetype)sizeWithWidthDimension:(NSCollectionLayoutDimension *)width heightDimension:(NSCollectionLayoutDimension *)height {
    if (!width.isAbsolute || width.dimension < kSmallest || sg_containerWidth <= 0) return %orig;
    BOOL sized = height.isAbsolute || height.isEstimated;
    // The cards come first, then the row that holds them all (1634 by 195 on the phone): the row is as many cards
    // wide, so it widens as much, but grows in height only as much as a card does.
    if (sg_cardWidth == 0 || width.dimension < sg_cardWidth) {
        sg_cardWidth = width.dimension;
        if (sized) sg_cardGrow = MAX(0, targetWidth() + kFooter - height.dimension);
    }
    if (!sg_enlarging || !sized || sg_cardGrow <= 0) return %orig;
    CGFloat scale = targetWidth() / sg_cardWidth;
    NSCollectionLayoutDimension *wider = [NSCollectionLayoutDimension absoluteDimension:round(width.dimension * scale)];
    NSCollectionLayoutDimension *taller = height.isAbsolute ? [NSCollectionLayoutDimension absoluteDimension:height.dimension + sg_cardGrow]
                                                            : [NSCollectionLayoutDimension estimatedDimension:height.dimension + sg_cardGrow];
    return %orig(wider, taller);
}
%end

%hook _TtC12Element_List18CollectionViewCell
- (UICollectionViewLayoutAttributes *)preferredLayoutAttributesFittingAttributes:(UICollectionViewLayoutAttributes *)attributes {
    UICollectionViewLayoutAttributes *result = %orig;
    static Class shelf;
    if (!shelf) shelf = NSClassFromString(@"_TtC16Home_CarouselKit29TouchCancellingCollectionView");
    UIView *content = ((UICollectionViewCell *)self).contentView.subviews.firstObject;
    // Home's sections only, as HomeSections.x tells them: a shelf on another page is not Home's top.
    if (![NSStringFromClass(object_getClass(content)) containsString:@"Home_EvoPageImpl13HomeStructure"]) return result;
    UIView *root = content.subviews.firstObject;
    NSInteger index = attributes.indexPath.section * 10000 + attributes.indexPath.item;
    UIView *list = ((UIView *)self).superview;
    while (list && ![list isKindOfClass:UICollectionView.class]) list = list.superview;
    if (list) objc_setAssociatedObject(((UICollectionView *)list).collectionViewLayout, &kListKey, @YES, OBJC_ASSOCIATION_RETAIN_NONATOMIC);
    if (!shelf || ![root isKindOfClass:shelf] || result.size.height <= kHeading) {
        // The top's place holds something else now (the feed came again): the next shelf measured takes it.
        if (index == sg_topIndex) sg_topIndex = NSIntegerMax;
        // The shortcuts grid is the one bare list Home has (HomeSections.x); a section of anything else in its place
        // (no shortcuts) leaves the order alone.
        BOOL grid = [root isKindOfClass:UICollectionView.class] && !root.accessibilityIdentifier.length && result.size.height > 0;
        if (grid) sg_gridSection = attributes.indexPath.section;
        else if (attributes.indexPath.section == sg_gridSection) sg_gridSection = NSNotFound;
        return result;
    }
    UICollectionViewLayout *layout = ((UICollectionView *)root).collectionViewLayout;
    // The shelf drawn large: the one Cards from names, else the one nearest the top; never one switched off.
    NSString *identity = SGRHomeShelfIdentity(root), *from = SGRHomeTopPicksFrom();
    BOOL candidate = !SGRHomeShelfHidden(identity) && (!from || [identity isEqualToString:from]);
    if (candidate && index < sg_topIndex) sg_topIndex = index;
    else if (!candidate && index == sg_topIndex) sg_topIndex = NSIntegerMax;
    BOOL large = index == sg_topIndex, was = objc_getAssociatedObject(layout, &kLargeKey) != nil;
    if (large) sg_largeShelf = (UICollectionView *)root;
    // The shelf's height as Spotify sizes it, from a measuring before it was large.
    if (!was) objc_setAssociatedObject(layout, &kNaturalKey, @(result.size.height), OBJC_ASSOCIATION_RETAIN_NONATOMIC);
    if (large != was) {
        objc_setAssociatedObject(layout, &kLargeKey, large ? @YES : nil, OBJC_ASSOCIATION_RETAIN_NONATOMIC);
        [layout invalidateLayout];
        // The shelf laid its cells out at Spotify's sizes before the mark changed (reading its heading lays it out), and
        // a cell the new layout puts off screen kept its old frame on screen: the cells are made again from the new
        // layout, the heading with them.
        __weak UICollectionView *weakShelf = (UICollectionView *)root;
        dispatch_async(dispatch_get_main_queue(), ^{ [weakShelf reloadData]; });
        static dispatch_once_t once;
        dispatch_once(&once, ^{
            SGLog(@"redesign home: top picks at %ld, its layout %@ (%@)", (long)index, NSStringFromClass(layout.class),
                  objc_getAssociatedObject(layout, &kWrappedKey) ? @"sized by a provider" : @"not made by a provider: left as it is");
        });
    }
    NSNumber *natural = objc_getAssociatedObject(layout, &kNaturalKey);
    // Spotify's height for the shelf: its first measuring can be an estimate (244 for 235), so a lower one replaces
    // it. Measured with its cards drawn large it comes out taller, and is not taken: grown again, it would grow on
    // every pass.
    if (large && natural && result.size.height < natural.doubleValue) {
        natural = @(result.size.height);
        objc_setAssociatedObject(layout, &kNaturalKey, natural, OBJC_ASSOCIATION_RETAIN_NONATOMIC);
    }
    NSNumber *grow = objc_getAssociatedObject(layout, &kGrowKey);
    // The large shelf's heading goes (HomeHeadings.x), and so does the band it took: the shelf is scrolled past it
    // (keptAbove below), and its cell is that much shorter, so the cards sit kBandAbove under the page's title.
    CGFloat offset = 0;
    if (large) {
        CGRect first = [layout layoutAttributesForItemAtIndexPath:[NSIndexPath indexPathForItem:0 inSection:0]].frame;
        offset = MAX(0, CGRectGetMinY(first) - kBandAbove);
    }
    objc_setAssociatedObject(layout, &kOffsetKey, offset > 0 ? @(offset) : nil, OBJC_ASSOCIATION_RETAIN_NONATOMIC);
    // Never shorter than what the shelf lays out: Spotify's height can be taken before its tallest card sized
    // itself (a title on 4 lines), and the shelf then scrolls inside its cell. The shelf's height comes from its
    // cards, not from the cell, so taking it does not feed back.
    if (natural && large && grow) result.size = CGSizeMake(result.size.width, MAX(natural.doubleValue + grow.doubleValue,
                                                                              ceil(layout.collectionViewContentSize.height)) - offset);
    else if (natural && was) result.size = CGSizeMake(result.size.width, natural.doubleValue);
    return result;
}
%end

static CGFloat keptAbove(UICollectionView *shelf) {
    return [objc_getAssociatedObject(shelf.collectionViewLayout, &kOffsetKey) doubleValue];
}

%hook _TtC16Home_CarouselKit29TouchCancellingCollectionView
// The large shelf's cards sized themselves after its cell was measured and no longer fit: measure the cell again.
- (void)setContentSize:(CGSize)size {
    %orig;
    UICollectionView *shelf = (UICollectionView *)self;
    UICollectionViewLayout *layout = shelf.collectionViewLayout;
    if (!objc_getAssociatedObject(layout, &kLargeKey) || size.height - keptAbove(shelf) <= shelf.bounds.size.height + 0.5) return;
    NSNumber *asked = objc_getAssociatedObject(layout, &kAskedKey);
    if (asked && asked.doubleValue == size.height) return;
    objc_setAssociatedObject(layout, &kAskedKey, @(size.height), OBJC_ASSOCIATION_RETAIN_NONATOMIC);
    UIView *cell = shelf.superview;
    while (cell && ![cell isKindOfClass:UICollectionViewCell.class]) cell = cell.superview;
    dispatch_async(dispatch_get_main_queue(), ^{ [cell invalidateIntrinsicContentSize]; });
}

// VoiceOver reads a list's cells in their index order, which the swap no longer draws: the page's list reads
// them in the order they are on screen.
- (NSArray *)accessibilityElements {
    UICollectionView *list = (UICollectionView *)self;
    if (!objc_getAssociatedObject(list.collectionViewLayout, &kListKey) || sg_gridSection == NSNotFound) return %orig;
    NSArray<UICollectionViewCell *> *cells = [list.visibleCells sortedArrayUsingComparator:^NSComparisonResult(UIView *a, UIView *b) {
        return a.frame.origin.y < b.frame.origin.y ? NSOrderedAscending : a.frame.origin.y > b.frame.origin.y ? NSOrderedDescending : NSOrderedSame;
    }];
    NSMutableArray *elements = [NSMutableArray array];
    for (UICollectionViewCell *cell in cells) {
        if (!cell.accessibilityElementsHidden && cell.bounds.size.height > 0) [elements addObject:cell];
    }
    return elements;
}

// The large shelf stays scrolled past its heading, and cannot be dragged back down to it: its own vertical pan
// goes, the cards' sideways one being the orthogonal scroll view's. A shelf no longer large gets the pan back.
- (void)layoutSubviews {
    %orig;
    CFTimeInterval began = SGRHomeProbeBegin();
    UICollectionView *shelf = (UICollectionView *)self;
    CGFloat above = keptAbove(shelf);
    BOOL held = objc_getAssociatedObject(shelf, &kHeldKey) != nil;
    // Every shelf and the page's list are this class: only the large one, or one that was, has work here.
    if (above <= 0 && !held) {
        SGRHomeProbeEnd(SGRHomeProbeShelfLayout, began);
        return;
    }
    // The heading goes with the band (its point still in view would show a sliver), and comes back with it. Set
    // here, on the shelf's own pass, since the heading's button lays out before the shelf is marked and not after.
    UIView *heading = SGRFindByIdentifier(shelf, @"Components.UI.SectionHeadingHome", &kHeadingKey);
    if (heading && heading.alpha != (above > 0 ? 0 : 1)) {
        heading.alpha = above > 0 ? 0 : 1;
        heading.userInteractionEnabled = above <= 0;
        heading.accessibilityElementsHidden = above > 0;
    }
    if (above > 0) {
        if (shelf.contentOffset.y != above) shelf.contentOffset = CGPointMake(shelf.contentOffset.x, above);
        if (shelf.scrollEnabled) shelf.scrollEnabled = NO;
        // The heading scrolled past the top would draw over the page's title otherwise: Spotify's shelf does not clip.
        if (!shelf.clipsToBounds) shelf.clipsToBounds = YES;
        if (!held) objc_setAssociatedObject(shelf, &kHeldKey, @YES, OBJC_ASSOCIATION_RETAIN_NONATOMIC);
    } else if (held) {
        objc_setAssociatedObject(shelf, &kHeldKey, nil, OBJC_ASSOCIATION_RETAIN_NONATOMIC);
        shelf.scrollEnabled = YES;
        shelf.clipsToBounds = NO;
    }
    SGRHomeProbeEnd(SGRHomeProbeShelfLayout, began);
}
%end

UIControl *SGRHomeTopPicksShowAll(NSString **title) {
    UICollectionView *shelf = sg_largeShelf;
    if (!shelf.window) return nil;
    UIView *showAll = SGRFindByIdentifier(shelf, @"Components.UI.NavigationButtonHome", &kShowAllKey);
    __block UIControl *control = [showAll isKindOfClass:UIControl.class] ? (UIControl *)showAll : nil;
    if (!control) SGForEachView(showAll, ^(UIView *v) {
        if (!control && [v isKindOfClass:UIControl.class]) control = (UIControl *)v;
    });
    if (!control || showAll.bounds.size.width < 1) return nil;
    for (UIView *v = showAll; v && v != shelf; v = v.superview) {
        if (v.hidden) return nil;
    }
    if (title) *title = SGRHomeShelfTitle(shelf);
    return control;
}

#pragma mark - the large card

static char kPartsKey, kCoverKey, kShownKey;

@interface SGRLargeCardParts : NSObject
@property (nonatomic, strong) UIView *surface;
@property (nonatomic, strong) UILabel *lead, *second;
@property (nonatomic, copy) NSArray<UILabel *> *theirs;   // Spotify's labels made transparent, to bring back
@end
@implementation SGRLargeCardParts
@end

static UILabel *footerLabel(UIFont *font, UIColor *color) {
    UILabel *label = [UILabel new];
    label.font = font;
    label.textColor = color;
    label.lineBreakMode = NSLineBreakByTruncatingTail;
    label.userInteractionEnabled = NO;
    label.accessibilityElementsHidden = YES;   // the button reads the whole card out already
    return label;
}

static BOOL shown(UIView *view, UIView *root) {
    for (UIView *v = view; v && v != root; v = v.superview) {
        if (v.hidden) return NO;
    }
    return YES;
}

// Spotify's labels with text, top to bottom: its first line, then its second (the kind over the name on a
// "More like" card, the name over "Album • Artist" in Recents), then the sponsored line when there is one.
static NSArray<UILabel *> *spotifyLabels(UIView *card, SGRLargeCardParts *parts) {
    NSMutableArray<UILabel *> *labels = [NSMutableArray array];
    SGForEachView(card, ^(UIView *v) {
        if (![v isKindOfClass:UILabel.class] || v == parts.lead || v == parts.second) return;
        if (((UILabel *)v).text.length && shown(v, card)) [labels addObject:(UILabel *)v];
    });
    return [labels sortedArrayUsingComparator:^NSComparisonResult(UILabel *a, UILabel *b) {
        CGFloat ya = [a convertRect:a.bounds toView:card].origin.y, yb = [b convertRect:b.bounds toView:card].origin.y;
        return ya < yb ? NSOrderedAscending : ya > yb ? NSOrderedDescending : NSOrderedSame;
    }];
}

static void restore(UIView *card, SGRLargeCardParts *parts) {
    UIView *holder = SGRFindByIdentifier(card, @"Encore.ImageView", &kCoverKey);
    if (holder && !CGAffineTransformIsIdentity(holder.transform)) holder.transform = CGAffineTransformIdentity;
    [parts.surface removeFromSuperview];
    [parts.lead removeFromSuperview];
    [parts.second removeFromSuperview];
    for (UILabel *label in parts.theirs) label.alpha = 1;
    objc_setAssociatedObject(card, &kPartsKey, nil, OBJC_ASSOCIATION_RETAIN_NONATOMIC);
    objc_setAssociatedObject(card, &kShownKey, nil, OBJC_ASSOCIATION_RETAIN_NONATOMIC);
}

static void setColor(SGRLargeCardParts *parts, UIColor *color, BOOL animated) {
    color = color ?: SGRElevated(UIColor.blackColor);
    if ([parts.surface.backgroundColor isEqual:color]) return;
    if (!animated || !parts.surface.window) {
        parts.surface.backgroundColor = color;
        return;
    }
    SGRAnimate(SGRMotionFade, ^{ parts.surface.backgroundColor = color; }, nil);
}

// The first card of the large shelf: the page takes its color.
static BOOL isFirstCard(UIView *card) {
    UIView *cell = card;
    while (cell && ![cell isKindOfClass:UICollectionViewCell.class]) cell = cell.superview;
    UICollectionView *shelf = sg_largeShelf;
    if (!cell || !shelf || ![cell isDescendantOfView:shelf]) return NO;
    NSIndexPath *path = [shelf indexPathForCell:(UICollectionViewCell *)cell];
    return path && path.item == 0;
}

static void tintCard(UIView *card, UIImageView *cover) {
    SGRLargeCardParts *parts = objc_getAssociatedObject(card, &kPartsKey);
    UIImage *image = cover.image;
    if (!parts) return;
    if (!image || !SGEnabled(SGRKeyHomeTopPicksColour)) {
        objc_setAssociatedObject(card, &kShownKey, nil, OBJC_ASSOCIATION_RETAIN_NONATOMIC);
        setColor(parts, nil, NO);
        if (isFirstCard(card)) SGRHomeSetPageTint(nil);
        return;
    }
    if (objc_getAssociatedObject(card, &kShownKey) == image) return;
    objc_setAssociatedObject(card, &kShownKey, image, OBJC_ASSOCIATION_RETAIN_NONATOMIC);
    __weak UIView *weakCard = card;
    SGRHomeTintForCover(image, ^(UIColor *color) {
        UIView *strongCard = weakCard;
        // A card reused for another cover in the meantime has asked for that one.
        if (!strongCard || objc_getAssociatedObject(strongCard, &kShownKey) != image) return;
        SGRLargeCardParts *now = objc_getAssociatedObject(strongCard, &kPartsKey);
        if (now) setColor(now, color, YES);
        if (isFirstCard(strongCard)) SGRHomeSetPageTint(color);
    });
}

static BOOL styleLargeCard(UIView *card);
BOOL SGRHomeStyleLargeCard(UIView *card) {
    CFTimeInterval began = SGRHomeProbeBegin();
    BOOL styled = styleLargeCard(card);
    SGRHomeProbeEnd(SGRHomeProbeLargeCard, began);
    return styled;
}
static BOOL styleLargeCard(UIView *card) {
    SGRLargeCardParts *parts = objc_getAssociatedObject(card, &kPartsKey);
    UIView *holder = SGRFindByIdentifier(card, @"Encore.ImageView", &kCoverKey);
    UIImageView *cover = nil;
    for (UIView *sub in holder.subviews) {
        if ([sub isKindOfClass:UIImageView.class]) cover = (UIImageView *)sub;
    }
    if (card.bounds.size.width < kLargeCard || !cover) {
        if (parts) restore(card, parts);
        return NO;
    }
    if (!parts) {
        parts = [SGRLargeCardParts new];
        parts.surface = [UIView new];
        parts.surface.userInteractionEnabled = NO;
        parts.surface.backgroundColor = SGRElevated(UIColor.blackColor);
        parts.lead = footerLabel(SGRFont(UIFontTextStyleBody, UIFontWeightSemibold, UIContentSizeCategoryLarge), SGRPrimary());
        parts.second = footerLabel(SGRFont(UIFontTextStyleFootnote, UIFontWeightRegular, UIContentSizeCategoryLarge), SGRSecondary());
        objc_setAssociatedObject(card, &kPartsKey, parts, OBJC_ASSOCIATION_RETAIN_NONATOMIC);
        __weak UIView *weakCard = card;
        // The block is replaced on every pass, so a cover taken into another card tells the card it is in now.
        SGRObserveImage(cover, ^(UIImageView *view) {
            UIView *strongCard = weakCard;
            if (strongCard && [view isDescendantOfView:strongCard]) tintCard(strongCard, view);
        });
        static dispatch_once_t once;
        dispatch_once(&once, ^{ SGLog(@"redesign home: top picks card %@ styled", NSStringFromCGRect(card.bounds)); });
    }
    CALayer *layer = card.layer;
    if (layer.cornerRadius != SGRRadiusCard) layer.cornerRadius = SGRRadiusCard;
    if (layer.cornerCurve != kCACornerCurveContinuous) layer.cornerCurve = kCACornerCurveContinuous;
    if (!layer.masksToBounds) layer.masksToBounds = YES;
    CALayer *coverLayer = cover.layer;
    if (coverLayer.cornerRadius != SGRRadiusCard) coverLayer.cornerRadius = SGRRadiusCard;
    if (coverLayer.cornerCurve != kCACornerCurveContinuous) coverLayer.cornerCurve = kCACornerCurveContinuous;
    CACornerMask top = kCALayerMinXMinYCorner | kCALayerMaxXMinYCorner;
    if (coverLayer.maskedCorners != top) coverLayer.maskedCorners = top;
    if (!coverLayer.masksToBounds) coverLayer.masksToBounds = YES;
    // Spotify keeps the cover 2pt in from the card on every side (9.1.90; none on 9.1.78); the reference's reaches
    // the card's top and sides, so the holder is scaled up about its middle by what the inset takes, a transform its
    // layout never reads. Only once Spotify has laid the holder out to the card (HomeCards.x asks for this pass
    // again when it does): scaled from its first, small size, the cover filled the whole card.
    CGAffineTransform was = holder.transform;
    holder.transform = CGAffineTransformIdentity;
    CGRect laid = [holder.superview convertRect:holder.frame toView:card];
    CGFloat inset = CGRectGetMinX(laid), cardWidth = card.bounds.size.width;
    CGAffineTransform flush = was;
    if (inset > 0 && inset <= 4 && fabs(CGRectGetWidth(laid) + inset * 2 - cardWidth) < 1) {
        flush = CGAffineTransformMakeScale(cardWidth / CGRectGetWidth(laid), cardWidth / CGRectGetWidth(laid));
    } else if (CGRectGetWidth(laid) + 1 < cardWidth - 4) {
        flush = CGAffineTransformIdentity;
    }
    holder.transform = flush;

    if (parts.surface.superview != card) [card insertSubview:parts.surface atIndex:0];
    if (!CGRectEqualToRect(parts.surface.frame, card.bounds)) parts.surface.frame = card.bounds;

    NSArray<UILabel *> *theirs = spotifyLabels(card, parts);
    for (UILabel *label in theirs) {
        if (label.alpha != 0) label.alpha = 0;
    }
    if (![parts.theirs isEqualToArray:theirs]) {
        for (UILabel *label in parts.theirs) {
            if (![theirs containsObject:label]) label.alpha = 1;
        }
        parts.theirs = theirs;
    }
    // Spotify's lines in Spotify's order, the first bold and the rest on one line ("Album" over "Name – Artist"
    // for a card of three). A sponsored card's "Limited ads" is an ad's line and stays out.
    NSMutableArray<NSString *> *lines = [NSMutableArray array];
    for (UILabel *label in theirs) {
        if (![label.accessibilityIdentifier containsString:@"SponsoredLabel"]) [lines addObject:label.text];
    }
    NSString *lead = lines.firstObject;
    NSString *second = lines.count > 1 ? [[lines subarrayWithRange:NSMakeRange(1, lines.count - 1)] componentsJoinedByString:@" – "] : nil;
    // An album's "Album • Kendrick Lamar" under "DAMN." leads with the kind, "DAMN. – Kendrick Lamar" under it.
    NSRange dot = lines.count > 1 ? [lines[1] rangeOfString:@" • "] : NSMakeRange(NSNotFound, 0);
    if (dot.location != NSNotFound && dot.location > 0) {
        lead = [lines[1] substringToIndex:dot.location];
        second = [NSString stringWithFormat:@"%@ – %@", lines[0], [lines[1] substringFromIndex:NSMaxRange(dot)]];
    }
    if (![parts.lead.text isEqualToString:lead]) parts.lead.text = lead;
    if (second ? ![parts.second.text isEqualToString:second] : parts.second.text != nil) parts.second.text = second;
    if (parts.lead.superview != card) [card addSubview:parts.lead];
    if (parts.second.superview != card) [card addSubview:parts.second];

    // The footer is the card's bottom kFooter: the card is that much taller than its cover is wide. Spotify's stack
    // lays the cover out after this pass, so its frame is not the one to go by.
    CGFloat footerTop = card.bounds.size.height - kFooter;
    CGFloat x = kFooterInset, width = MAX(0, card.bounds.size.width - x * 2);
    CGFloat leadHeight = ceil(parts.lead.font.lineHeight), secondHeight = ceil(parts.second.font.lineHeight);
    CGRect leadFrame = CGRectMake(x, footerTop + kFooterTop, width, leadHeight);
    CGRect secondFrame = CGRectMake(x, CGRectGetMaxY(leadFrame) + kFooterGap, width, secondHeight);
    if (!CGRectEqualToRect(parts.lead.frame, leadFrame)) parts.lead.frame = leadFrame;
    if (!CGRectEqualToRect(parts.second.frame, secondFrame)) parts.second.frame = secondFrame;
    tintCard(card, cover);
    return YES;
}

BOOL SGRHomeInTopPicks(UIView *view) {
    static Class shelf;
    if (!shelf) shelf = NSClassFromString(@"_TtC16Home_CarouselKit29TouchCancellingCollectionView");
    for (UIView *v = view; v; v = v.superview) {
        if (shelf && [v isKindOfClass:shelf]) return objc_getAssociatedObject(((UICollectionView *)v).collectionViewLayout, &kLargeKey) != nil;
    }
    return NO;
}

SGModRow *SGRHomeTopPicksRow(void) {
    return SGWithSymbol(SGSwitchRow(@"Top picks", @"Home's first shelf above the shortcuts, as large cards in their covers' colors", SGRKeyHomeTopPicks), @"rectangle.stack");
}

%ctor {
    if (!SGRedesignedUI() || !SGRHomeLook() || !SGEnabled(SGRKeyHomeTopPicks)) return;
    %init;
}
