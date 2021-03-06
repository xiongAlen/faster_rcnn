% RPN and FCNtraining and testing on ilsvrc
%
% refactor by hyli on July 28, 2016
% ---------------------------------------------------------
caffe.reset_all();
clear; run('./startup');
%% init
fprintf('\nInitialize model, dataset, and configuration...\n');
opts.do_val = true;
% ===========================================================
% ======================= USER DEFINE =======================
use_flipped = false;
opts.gpu_id = 2;
% opts.train_key = 'train_val1';
opts.train_key = 'train14';
% load paramters from the 'models' folder
model = Model.VGG16_for_Faster_RCNN(...
    'solver_10w30w_ilsvrc_9anchor', 'test_9anchor', ...     % rpn
    'solver_5w15w_2', 'test_2' ...                          % fast_rcnn
    );
% --------------------------- FCN ----------------------------
fast_rcnn_net_file = [{'train14'}, {'final'}];
% if you want to generate new train_val_data, 'update_roi' must be set
% true; otherwise you can set it false to directly use existing data.
% update: you MUST update roi when test (TODO: explain more here).
update_roi                  = true;
update_roi_name             = '1';
%update_roi_name             = 'M27_nms0.55';      % name in the imdb folder after adding NMS additional boxes

binary_train                = true;
% FCN cache folder name
%cache_base_FCN              = 'FCN_try_local';
cache_base_FCN              = 'F02_ls149';
share_data_FCN              = '';
fcn_fg_thresh               = 0.5;
fcn_bg_thresh_hi            = 0.5;
fcn_bg_thresh_lo            = 0.1;
fcn_scales                  = [600];
fcn_fg_fraction             = 0.25;
fcn_max_size                = 1000;

fast_rcnn_after_nms_topN    = 2000;
fast_nms_overlap_thres = [0.8, 0.75, 0.7, 0.65, 0.6, 0.55, 0.5, 0.45, 0.4];
% --------------------------- RPN ----------------------------
% NOTE: this variable stores BOTH RPN and FCN in the 'config_temp' folder
% cache_base_RPN = 'NEW_ILSVRC_ls139';
cache_base_RPN = 'M02_s31';
% share_data_RPN = 'M04_ls149';
share_data_RPN = '';
% won't do test and compute recall
skip_rpn_test               = true;

model.anchor_size = 2.^(3:5);
model.ratios = [0.5, 1, 2];
detect_exist_config_file    = true;
detect_exist_train_file     = true;

% model.stage1_rpn.nms.note = '0.55';   % must be a string
% model.stage1_rpn.nms.nms_overlap_thres = 0.55;

% model.stage1_rpn.nms.note = 'multiNMS_1a';   % must be a string
% default
% model.stage1_rpn.nms.nms_iou_thrs   = [0.95, 0.90, 0.85, 0.80, 0.75, 0.65, 0.60, 0.55];
% model.stage1_rpn.nms.max_per_image  = [2000, 1000,  400,  200,  100,   40,   20,   10];
fg_thresh = 0.5;        % 0.7 default
bg_thresh_hi = 0.5;     % 0.3 default
scales = [600];
% ==========================================================
% ==========================================================
model.stage1_rpn.nms.mult_thr_nms = false;
if isnan(str2double(model.stage1_rpn.nms.note)), model.stage1_rpn.nms.mult_thr_nms = true; end
model = Faster_RCNN_Train.set_cache_folder(cache_base_RPN, cache_base_FCN, model);
% finetune
if exist('ft_file', 'var')
    net_file = ft_file;
    fprintf('\ninit from another model\n');
else
    net_file = model.stage1_rpn.init_net_file;
end
caffe.set_device(opts.gpu_id);
caffe.set_mode_gpu();
% config, must be input after setting caffe
% in the 'proposal_config.m' file
% TODO change the saving mechanism here
[conf_proposal, conf_fast_rcnn] = Faster_RCNN_Train.set_config( ...
    cache_base_RPN, model, detect_exist_config_file );
conf_proposal.cache_base_proposal = cache_base_RPN;
conf_proposal.fg_thresh = fg_thresh;
conf_proposal.bg_thresh_hi = bg_thresh_hi;
conf_proposal.scales = scales;

if isempty(share_data_FCN)
    conf_fast_rcnn.data_name = cache_base_FCN;
else
    conf_fast_rcnn.data_name = share_data_FCN;
end

conf_fast_rcnn.fcn_fg_thresh        = fcn_fg_thresh;
conf_fast_rcnn.fcn_bg_thresh_hi     = fcn_bg_thresh_hi;
conf_fast_rcnn.fcn_bg_thresh_lo     = fcn_bg_thresh_lo;
conf_fast_rcnn.fcn_scales           = fcn_scales;
conf_fast_rcnn.fcn_fg_fraction      = fcn_fg_fraction;
conf_fast_rcnn.fcn_max_size         = fcn_max_size;
conf_fast_rcnn.update_roi_name      = update_roi_name;

% train/test data
% init:
%   imdb_train, roidb_train, cell;
%   imdb_test, roidb_test, struct
dataset = [];
% change to point to your devkit install
root_path = './datasets/ilsvrc14_det';
dataset = Dataset.ilsvrc14(dataset, 'test', false, root_path);
dataset = Dataset.ilsvrc14(dataset, opts.train_key, use_flipped, root_path);

%%  stage one proposal
% % temporarily comment the following
% cprintf('blue', '\nStage one proposal TRAINING...\n');
% % train
% model.stage1_rpn.output_model_file = proposal_train(...
%     conf_proposal, ...
%     dataset.imdb_train, dataset.roidb_train, opts.train_key, ...
%     'detect_exist_train_file',  detect_exist_train_file, ...
%     'do_val',               opts.do_val, ...
%     'imdb_val',             dataset.imdb_test, ...
%     'roidb_val',            dataset.roidb_test, ...
%     'solver_def_file',      model.stage1_rpn.solver_def_file, ...
%     'net_file',             net_file, ...
%     'cache_name',           model.stage1_rpn.cache_name, ...
%     'snapshot_interval',    20000, ...
%     'share_data_name',      share_data_RPN ...
%     );

% test: compute recall and update roidb on TEST
cprintf('blue', '\nStage one proposal TEST on val data ...\n');
dataset.roidb_test = RPN_TEST_ilsvrc_hyli(...
    'train14', 'final', model, ...
    dataset.imdb_test, dataset.roidb_test, conf_proposal, ...
    'mult_thr_nms',         model.stage1_rpn.nms.mult_thr_nms, ...
    'nms_iou_thrs',         model.stage1_rpn.nms.nms_iou_thrs, ...
    'max_per_image',        model.stage1_rpn.nms.max_per_image, ...
    'update_roi',           update_roi, ...
    'update_roi_name',      update_roi_name, ...
    'skip_rpn_test',        skip_rpn_test, ...
    'gpu_id',               opts.gpu_id ...
    );

% % test: compute recall and update roidb on TRAIN
% cprintf('blue', '\nStage one proposal TEST on train data...\n');
% dataset.roidb_train = cellfun(@(x,y) RPN_TEST_ilsvrc_hyli(...
%     'train14', 'final', model, x, y, conf_proposal, ...
%     'mult_thr_nms',         model.stage1_rpn.nms.mult_thr_nms, ...
%     'nms_iou_thrs',         model.stage1_rpn.nms.nms_iou_thrs, ...
%     'max_per_image',        model.stage1_rpn.nms.max_per_image, ...
%     'update_roi',           update_roi, ...
%     'update_roi_name',      update_roi_name, ...
%     'skip_rpn_test',        skip_rpn_test, ...
%     'gpu_id',               opts.gpu_id ...
%     ), dataset.imdb_train, dataset.roidb_train, 'UniformOutput', false);

%% fast rcnn train
% add more proposal here
% if adding more proposals, you need to increase the number here
test_max_per_image          = 10001; %10000; %100;
% if avg == max_per_im, there's no reduce in the number of boxes.
test_avg_per_image          = 10001; %10000; %500; %40;

% the name where new roidb resides
name = 'new_roidb_file_rpn_only';
mkdir_if_missing(['./imdb/cache/ilsvrc/' name]);
FLIP = 'unflip';
% the newly generated boxes after testing
new_box_prefix = './output/fast_rcnn_cachedir/F02_ls149_nms0_7_top2000_stage1_fast_rcnn/ilsvrc14_val2/final';

box_name = sprintf('binary_boxes_ilsvrc14_val2_max_%d_avg_%d', ...
    test_max_per_image, test_avg_per_image);
keep_raw = false;

% store the new roidb in the following folder
new_roidb_file = @(x) fullfile(pwd, 'imdb/cache/ilsvrc', name, ...
    ['roidb_' dataset.roidb_test.name '_' FLIP sprintf('_iter_%d.mat', x)]);
test_sub_folder_suffix = @(x) sprintf('F24_%d', x);

for i = 1:7
       
    if ~exist(new_roidb_file(i), 'file')
        % load boxes in the last iteration
        if i == 1
            load_name = [new_box_prefix '/' ...
                'binary_boxes_ilsvrc14_val2_max_2000_avg_2000.mat'];
        else
            load_name = [new_box_prefix '_' ...
                test_sub_folder_suffix(i-1) '/' box_name]; 
        end
        ld = load(load_name);
        aboxes = ld.boxes;
        
        roidb_regions = [];
        roidb_regions.boxes = aboxes;
        roidb_regions.images = dataset.imdb_test.image_ids;
        % update roidb in 'imdb' folder
        roidb_from_proposal(dataset.imdb_test, dataset.roidb_test, ...
            roidb_regions, 'keep_raw_proposal', keep_raw, 'mat_file', new_roidb_file(i));
    end
    ld = load(new_roidb_file(i));
    dataset.roidb_test.rois = ld.rois;
    
    cprintf('blue', '\nStage two Fast-RCNN cascade TEST...\n');
    fast_rcnn_test(conf_fast_rcnn, dataset.imdb_test, dataset.roidb_test, ...
        'net_def_file',             model.stage1_fast_rcnn.test_net_def_file, ...
        'net_file',                 fast_rcnn_net_file, ...
        'cache_name',               model.stage1_fast_rcnn.cache_name, ...
        'binary',                   binary_train, ...
        'max_per_image',            test_max_per_image, ...
        'avg_per_image',            test_avg_per_image, ...
        'nms_overlap_thres',        fast_nms_overlap_thres, ...
        'test_sub_folder_suffix',   test_sub_folder_suffix(i), ...
        'after_nms_topN',           fast_rcnn_after_nms_topN ...
        );
end
exit;
