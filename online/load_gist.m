function [Xtrain, Ytrain, Xtest, Ytest, thr_dist] = load_gist(opts, normalizeX)
% Load and prepare GIST features. The data paths must be changed. For all datasets,
% X represents the data matrix. Rows correspond to data instances and columns
% correspond to variables/features.
% Y represents the label matrix where each row corresponds to a label vector of 
% an item, i.e., for multiclass datasets this vector has a single dimension and 
% for multilabel datasets the number of columns of Y equal the number of labels
% in the dataset. Y can be empty for unsupervised datasets.
% 
%
% INPUTS
%	opts   - (struct)  Parameter structure.
%   normalizeX - (int)     Choices are {0, 1}. If normalizeX = 1, the data is 
% 			   mean centered and unit-normalized. 
% 		
% OUTPUTS
% 	Xtrain - (nxd) 	   Training data matrix, each row corresponds to a data
%			   instance.
%	Ytrain - (nxl)     Training data label matrix. l=1 for multiclass datasets.
%			   For unsupervised dataset Ytrain=[], see LabelMe in 
%			   load_gist.m
%	Xtest  - (nxd)     Test data matrix, each row corresponds to a data instance.
%	Ytest  - (nxl)	   Test data label matrix, l=1 for multiclass datasets. 
%			   For unsupervised dataset Ytrain=[], see LabelMe in 
%			   load_gist.m
%	thr_dist - (int)   For unlabelled datasets, corresponds to the distance 
%			   value to be used in determining whether two data instance
% 			   are neighbors. If their distance is smaller, then they are
% 			   considered neighbors.
%			   Given the standard setup, this threshold value
%			   is hard-wired to be compute from the 5th percentile 
% 			   distance value obtain through 2,000 training instance. 
% 			   See labelme case below.
%
if nargin < 2, normalizeX = 1; end
if ~normalizeX, logInfo('will NOT pre-normalize data'); end
thr_dist = -Inf;
basedir = '/research/codebooks/hashing_project/data';

tic;
if strcmp(opts.dataset, 'cifar')
    load([basedir '/cifar-10/descriptors/gist.mat']);
    gist        = [traingist; testgist];
    gistlabels  = [trainlabels+1; testlabels+1];  % NOTE labels are 0 to 9
    gistlabels = gistlabels .* 10;
    tstperclass = 100;

    if normalizeX 
        % normalize features
        gist = bsxfun(@minus, gist, mean(gist,1));  % first center at 0
        gist = normalize(double(gist));  % then scale to unit length
    end
    [Xtrain, Ytrain, Xtest, Ytest] = ...
        split_train_test(gist, gistlabels, tstperclass);

    if opts.val_size > 0
	assert(length(Ytrain) >=  opts.val_size);
    	logInfo('Doing validation!');
	ind_ = randperm(length(Ytrain));
	Xtrain = Xtrain(ind_(1:opts.val_size), :);
	Ytrain = Ytrain(ind_(1:opts.val_size), :);
    end
elseif strcmp(opts.dataset, 'sun')
    load([basedir '/sun397/SUN_gist.mat']);
    gistlabels  = labels+1;  % NOTE labels are 0 to 396
    gistlabels = gistlabels .* 10;
    tstperclass = 10;

    if normalizeX 
        % normalize features
        gist = bsxfun(@minus, gist, mean(gist,1));  % first center at 0
        gist = normalize(double(gist));  % then scale to unit length
    end
    [Xtrain, Ytrain, Xtest, Ytest] = ...
        split_train_test(gist, gistlabels, tstperclass);

    if opts.val_size > 0
	assert(length(Ytrain) >=  opts.val_size);
    	logInfo('Doing validation!');
	ind_ = randperm(length(Ytrain));
	Xtrain = Xtrain(ind_(1:opts.val_size), :);
	Ytrain = Ytrain(ind_(1:opts.val_size), :);
    end
elseif strcmp(opts.dataset, 'nus')
    gist = load([basedir '/nuswide/BoW_int.dat']);
    tags = load([basedir '/nuswide/AllLabels81.txt']);
    
    use21FrequentConcepts = 1;
    if use21FrequentConcepts
    	logInfo('Using 21 most frequent concepts, removing rest...');
	[~, fi_] = sort(sum(tags, 1), 'descend');
	tags(:, fi_(22:end)) = [];
	fi2_ = find(sum(tags, 2) == 0);
	tags(fi2_,:) = [];
	gist(fi2_,:) = [];
	logInfo('No. of points=%g, dimensionality=%g, No. of labels=%g', ...
		size(gist,1), size(gist, 2), size(tags, 2));
    end
    tstperclass = 30;

    if normalizeX 
        % normalize features
        gist = bsxfun(@minus, gist, mean(gist,1));  % first center at 0
        gist = normalize(double(gist));  % then scale to unit length
    end
    [Xtrain, Ytrain, Xtest, Ytest] = ...
        split_train_test_nus(gist, tags, tstperclass, use21FrequentConcepts);
    if opts.val_size > 0
	assert(length(Ytrain) >=  opts.val_size);
    	logInfo('Doing validation!');
	ind_ = randperm(length(Ytrain));
	Xtrain = Xtrain(ind_(1:opts.val_size), :);
	Ytrain = Ytrain(ind_(1:opts.val_size), :);
    end
elseif strcmp(opts.dataset, 'labelme')
    load([basedir '/labelme/LabelMe_gist.mat'],'gist');
    no_tst = 1000;
    if normalizeX 
        % normalize features
        gist = bsxfun(@minus, gist, mean(gist,1));  % first center at 0
        gist = normalize(double(gist));  % then scale to unit length
    end
    [Xtrain, Ytrain, Xtest, Ytest, thr_dist] = ...
        split_train_test_unsupervised(gist, no_tst);
    if opts.val_size > 0
	assert(size(Xtrain, 1) >=  opts.val_size);
    	logInfo('Doing validation!');
	ind_ = randperm(length(Ytrain));
	Xtrain = Xtrain(ind_(1:opts.val_size), :);
    end
else, error(['unknown dataset: ' opts.dataset]); end

whos Xtrain Ytrain Xtest Ytest
logInfo('Dataset "%s" loaded in %.2f secs', opts.dataset, toc);
end

%---------------------------------------------------------
function [Xtrain, Ytrain, Xtest, Ytest, thr_dist] = ...
    split_train_test_unsupervised(gist, no_tst)

% normalize features
gist = bsxfun(@minus, gist, mean(gist,1));  % first center at 0
gist = normalize(gist);  % then scale to unit length

ind    = randperm(size(gist, 1));
Xtest  = gist(ind(1:no_tst),:);
Xtrain = gist(ind(no_tst+1:end),:);

assert(size(Xtrain, 1) >= 2000 );
% Compute threshold value from 2K and 5th percentile (hard wired)
thr_dist = prctile(pdist(Xtrain(1:2000,:),'euclidean'), 5); 
Ytrain = []; Ytest = [];
end

% --------------------------------------------------------
function [Xtrain, Ytrain, Xtest, Ytest] = ...
    split_train_test(gist, gistlabels, tstperclass)

% normalize features
gist = bsxfun(@minus, gist, mean(gist,1));  % first center at 0
gist = normalize(gist);  % then scale to unit length

% construct test and training set
clslbl      = unique(gistlabels);
num_classes = length(clslbl);
testsize    = num_classes * tstperclass;
trainsize   = size(gist, 1) - testsize;
gistdim     = size(gist, 2);
Xtest       = zeros(testsize, gistdim);
Ytest       = zeros(testsize, 1);
Xtrain      = zeros(trainsize, gistdim);
Ytrain      = zeros(trainsize, 1);
count = 0;
for i = 1:num_classes
    ind = find(gistlabels == clslbl(i));
    n_i = length(ind);
    ind = ind(randperm(n_i));
    Xtest((i-1)*tstperclass+1:i*tstperclass,:) = gist(ind(1:tstperclass),:);
    Ytest((i-1)*tstperclass+1:i*tstperclass)   = clslbl(i);
    Xtrain(count+1:count+n_i-tstperclass, :)   = gist(ind(tstperclass+1:end),:);
    Ytrain(count+1:count+n_i-tstperclass, :)   = clslbl(i);
    count = count + n_i - tstperclass;
end
% randomize again
ind    = randperm(size(Xtrain, 1));
Xtrain = Xtrain(ind, :);
Ytrain = Ytrain(ind);
ind    = randperm(size(Xtest, 1));
Xtest  = Xtest(ind, :);
Ytest  = Ytest(ind);

%cateTrainTest = repmat(Ytrain, 1, length(Ytest)) ...
%== repmat(Ytest, 1, length(Ytrain))';
end

% --------------------------------------------------------
function [Xtrain, Ytrain, Xtest, Ytest] = ...
    split_train_test_nus(gist, tags, tstperclass, ufq)

% normalize features
gist = bsxfun(@minus, gist, mean(gist,1));  % first center at 0
gist = normalize(gist);  % then scale to unit length

% construct test and training set
num_classes = size(tags, 2);
%num_classes = 81;
testsize    = num_classes * tstperclass;
ind         = randperm(size(gist, 1));
Xtest       = gist(ind(1:testsize), :);
Ytest       = tags(ind(1:testsize), :);
Xtrain      = gist(ind(testsize+1:end), :);
Ytrain      = tags(ind(testsize+1:end), :);

% randomize again
ind    = randperm(size(Xtrain, 1));
Xtrain = Xtrain(ind, :);
Ytrain = Ytrain(ind, :);
ind    = randperm(size(Xtest, 1));
Xtest  = Xtest(ind, :);
Ytest  = Ytest(ind, :);

% TODO after eliminating cateTrainTest, get_results will have to deal with
% the multi-label case explicitly
%cateTrainTest = (Ytrain * Ytest' > 0);
end
