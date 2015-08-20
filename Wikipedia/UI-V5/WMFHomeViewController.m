

#import "WMFHomeViewController.h"

#import "MWKSavedPageList.h"
#import "MWKRecentSearchList.h"

#import "WMFLocationManager.h"
#import "WMFLocationSearchFetcher.h"

#import "WMFNearbySectionController.h"

#import <SSDataSources/SSDataSources.h>
#import "SSSectionedDataSource+WMFSectionConvenience.h"

#import "MWKDataStore.h"
#import "MWKSavedPageList.h"
#import "MWKRecentSearchList.h"

#import "MWKSite.h"
#import "MWKLocationSearchResult.h"
#import "MWKTitle.h"
#import "MWKArticle.h"

#import "WMFHomeSectionHeader.h"
#import "WMFHomeSectionFooter.h"

#import "WMFArticleContainerViewController.h"


NS_ASSUME_NONNULL_BEGIN

@interface WMFHomeViewController ()<WMFHomeSectionControllerDelegate>

@property (nonatomic, strong) WMFNearbySectionController* nearbySectionController;

@property (nonatomic, strong) WMFLocationManager* locationManager;
@property (nonatomic, strong) WMFLocationSearchFetcher* locationSearchFetcher;
@property (nonatomic, strong) SSSectionedDataSource* dataSource;

@property (nonatomic, strong) NSMutableDictionary* sectionControllers;

@end

@implementation WMFHomeViewController

#pragma mark - Accessors

- (WMFNearbySectionController*)nearbySectionController {
    if (!_nearbySectionController) {
        _nearbySectionController = [[WMFNearbySectionController alloc] initWithLocationManager:self.locationManager locationSearchFetcher:self.locationSearchFetcher];
        _nearbySectionController.delegate = self;
    }
    return _nearbySectionController;
}

- (WMFLocationManager*)locationManager {
    if (!_locationManager) {
        _locationManager = [[WMFLocationManager alloc] init];
    }
    return _locationManager;
}

- (WMFLocationSearchFetcher*)locationSearchFetcher {
    if (!_locationSearchFetcher) {
        _locationSearchFetcher = [[WMFLocationSearchFetcher alloc] initWithSearchSite:self.searchSite];
    }
    return _locationSearchFetcher;
}

- (SSSectionedDataSource*)dataSource {
    if (!_dataSource) {
        _dataSource = [[SSSectionedDataSource alloc] init];
        _dataSource.shouldRemoveEmptySections = NO;
    }
    return _dataSource;
}

- (NSMutableDictionary*)sectionControllers {
    if (!_sectionControllers) {
        _sectionControllers = [NSMutableDictionary new];
    }
    return _sectionControllers;
}

- (UICollectionViewFlowLayout*)flowLayout {
    return (id)self.collectionView.collectionViewLayout;
}

#pragma mark - UiViewController

- (void)viewDidLoad {
    [super viewDidLoad];
    
    self.navigationController.navigationBarHidden = NO;
    
    [self flowLayout].itemSize            = CGSizeMake(self.view.bounds.size.width - 20, 150.0);
    [self flowLayout].headerReferenceSize = CGSizeMake(self.view.bounds.size.width, 50.0);
    [self flowLayout].footerReferenceSize = CGSizeMake(self.view.bounds.size.width, 50.0);
    [self flowLayout].sectionInset        = UIEdgeInsetsMake(10.0, 0.0, 10.0, 0.0);
}

- (void)viewDidAppear:(BOOL)animated {

    NSParameterAssert(self.dataStore);
    NSParameterAssert(self.searchSite);
    NSParameterAssert(self.recentPages);
    NSParameterAssert(self.savedPages);

    [super viewDidAppear:animated];
    [self configureDataSource];
    [self.locationManager startMonitoringLocation];
}

- (void)viewDidDisappear:(BOOL)animated {
    [super viewDidDisappear:animated];
    [self.locationManager stopMonitoringLocation];
}

- (id<WMFHomeSectionController>)sectionControllerForSectionAtIndex:(NSInteger)index {
    SSSection* section = [self.dataSource sectionAtIndex:index];
    return self.sectionControllers[section.sectionIdentifier];
}

- (NSInteger)indexForSectionController:(id<WMFHomeSectionController>)controller{
    return (NSInteger)[self.dataSource indexOfSectionWithIdentifier:[controller sectionIdentifier]];
}

#pragma mark - Data Source Configuration

- (void)configureDataSource {
    if (_dataSource != nil) {
        return;
    }

    @weakify(self);

    self.dataSource.cellCreationBlock = (id) ^ (id object, id parentView, NSIndexPath * indexPath){
        @strongify(self);
        id<WMFHomeSectionController> controller = [self sectionControllerForSectionAtIndex:indexPath.section];
        return [controller dequeueCellForCollectionView:self.collectionView atIndexPath:indexPath];
    };

    self.dataSource.cellConfigureBlock = ^(id cell, id object, id parentView, NSIndexPath* indexPath){
        @strongify(self);
        id<WMFHomeSectionController> controller = [self sectionControllerForSectionAtIndex:indexPath.section];
        [controller configureCell:cell withObject:object atIndexPath:indexPath];
    };

    self.dataSource.collectionSupplementaryCreationBlock = (id) ^ (NSString * kind, UICollectionView * cv, NSIndexPath * indexPath){
        if ([kind isEqualToString:UICollectionElementKindSectionHeader]) {
            return (id)[WMFHomeSectionHeader supplementaryViewForCollectionView:cv kind:kind indexPath:indexPath];
        } else {
            return (id)[WMFHomeSectionFooter supplementaryViewForCollectionView:cv kind:kind indexPath:indexPath];
        }
    };

    self.dataSource.collectionSupplementaryConfigureBlock = ^(id view, NSString* kind, UICollectionView* cv, NSIndexPath* indexPath){
        @strongify(self);

        id<WMFHomeSectionController> controller = [self sectionControllerForSectionAtIndex:indexPath.section];

        if ([kind isEqualToString:UICollectionElementKindSectionHeader]) {
            WMFHomeSectionHeader* header = view;
            header.titleLabel.text = controller.headerText;
        } else {
            WMFHomeSectionFooter* footer = view;
            footer.moreLabel.text = controller.footerText;
        }
    };

    [self loadSectionForSectionController:self.nearbySectionController];
    self.dataSource.collectionView = self.collectionView;
}

- (void)loadSectionForSectionController:(id<WMFHomeSectionController>)controller{

    self.sectionControllers[controller.sectionIdentifier] = controller;
    
    [controller registerCellsInCollectionView:self.collectionView];
    
    SSSection* section = [SSSection sectionWithItems:[controller items]];
    section.sectionIdentifier = controller.sectionIdentifier;
    
    [self.collectionView performBatchUpdates:^{
        [self.dataSource appendSection:section];
    } completion:NULL];
}


#pragma mark - UICollectionViewDelegate

- (void)collectionView:(UICollectionView*)collectionView didSelectItemAtIndexPath:(NSIndexPath*)indexPath {
    
    id object = [self.dataSource itemAtIndexPath:indexPath];
    
    //TODO: Casting for now - ned to make a protocol or something
    MWKLocationSearchResult* result = object;
    MWKTitle* title = [[MWKSite siteWithCurrentLocale] titleWithString:result.displayTitle];
    [self showArticleViewControllerForTitle:title animated:YES];
}

#pragma mark - Article Presentation

- (void)showArticleViewControllerForTitle:(MWKTitle*)title animated:(BOOL)animated {
    
    MWKArticle* article  = [self.dataStore articleWithTitle:title];
    WMFArticleContainerViewController* articleContainerVC = [WMFArticleContainerViewController articleContainerViewControllerWithDataStore:article.dataStore savedPages:self.savedPages];
    articleContainerVC.article = article;
    [self.navigationController pushViewController:articleContainerVC animated:animated];
}

#pragma mark - WMFHomeSectionControllerDelegate

- (void)controller:(id<WMFHomeSectionController>)controller didSetItems:(NSArray*)items{
    
    NSInteger section = [self indexForSectionController:controller];
    [self.dataSource setItems:items inSection:section];
}

- (void)controller:(id<WMFHomeSectionController>)controller didAppendItems:(NSArray*)items{
    
    NSInteger section = [self indexForSectionController:controller];
    [self.dataSource appendItems:items toSection:section];
}

- (void)controller:(id<WMFHomeSectionController>)controller enumerateVisibleCells:(WMFHomeSectionCellEnumerator)enumerator{
    
    NSInteger section = [self indexForSectionController:controller];
    
    [self.collectionView.indexPathsForVisibleItems enumerateObjectsUsingBlock:^(NSIndexPath *obj, NSUInteger idx, BOOL *stop) {
        
        if(obj.section == section){
            enumerator([self.collectionView cellForItemAtIndexPath:obj], obj);
        }
    }];
}




@end


NS_ASSUME_NONNULL_END
