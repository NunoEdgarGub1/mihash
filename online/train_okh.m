function [train_time, update_time, res_time, ht_updates, bits_computed_all, bitflips] = ...
    train_okh(Xtrain, Ytrain, thr_dist,  prefix, test_iters, trialNo, opts)
% Training routine for OKH method, see demo_okh.m .
%
% INPUTS
% 	Xtrain - (float) n x d matrix where n is number of points 
%       	         and d is the dimensionality 
%
% 	Ytrain - (int)   n x l matrix containing labels, for unsupervised datasets
% 			 might be empty, e.g., LabelMe.
%     thr_dist - (int)   For unlabelled datasets, corresponds to the distance 
%		         value to be used in determining whether two data instance
% 		         are neighbors. If their distance is smaller, then they are
% 		         considered neighbors.
%	       	         Given the standard setup, this threshold value
%		         is hard-wired to be compute from the 5th percentile 
% 		         distance value obtain through 2,000 training instance.
% 			 see load_gist.m . 
% 	prefix - (string) Prefix of the "checkpoint" files.
%   test_iters - (int)   A vector specifiying the checkpoints, see train.m .
%   trialNo    - (int)   Trial ID
%	opts   - (struct)Parameter structure.
%
% OUTPUTS
%  train_time  - (float) elapsed time in learning the hash mapping
%  update_time - (float) elapsed time in updating the hash table
%  res_time    - (float) elapsed time in maintaing the reservoir set
%  ht_updates  - (int)   total number of hash table updates performed
%  bit_computed_all - (int) total number of bit recomputations, see update_hash_table.m
%  bitflips    - (int) total number of bit flips, see update_hash_table.m 
% 
% NOTES
% 	W is d x b where d is the dimensionality 
%            and b is the bit length / # hash functions
%
% 	If number_iterations is 1000, this means 2000 points will be processed, 
% 	data arrives in pairs

%%%%%%%%%%%%%%%%%%%%%%% GENERIC INIT %%%%%%%%%%%%%%%%%%%%%%%
% are we handling a mult-labeled dataset?
multi_labeled = (size(Ytrain, 2) > 1);
if multi_labeled, logInfo('Handling multi-labeled dataset'); end

% set up reservoir
reservoir = [];
reservoir_size = opts.reservoirSize;
if reservoir_size > 0
    reservoir.size = 0;
    reservoir.X    = [];
    reservoir.PQ   = [];
    reservoir.H    = [];  % mapped binary codes for the reservoir
    if opts.unsupervised
	reservoir.Y = [];
    else
        reservoir.Y  = zeros(0, size(Ytrain, 2));
    end
end

% order training examples
if opts.pObserve > 0
    % [OPTIONAL] order training points according to label arrival strategy
    train_ind = get_ordering(trialNo, Ytrain, opts);
else
    train_ind = zeros(1, opts.epoch*opts.noTrainingPoints);
    for e = 1:opts.epoch
	    % randomly shuffle training points before taking first noTrainingPoints
	    train_ind((e-1)*opts.noTrainingPoints+1:e*opts.noTrainingPoints) = ...
		randperm(size(Xtrain, 1), opts.noTrainingPoints);
    end
end
opts.noTrainingPoints = opts.noTrainingPoints*opts.epoch;
%%%%%%%%%%%%%%%%%%%%%%% GENERIC INIT %%%%%%%%%%%%%%%%%%%%%%%


%%%%%%%%%%%%%%%%%%%%%%% SET UP OKH %%%%%%%%%%%%%%%%%%%%%%%
tic;
% do kernel mapping to Xtrain
% KX: each COLUMN is a kernel-mapped training example
[KX, Xanchor, sigma] = init_okh(Xtrain);
para.c      = opts.c; %0.1;
para.alpha  = opts.alpha; %0.2;
para.anchor = Xanchor;

% for recording time
res_time    = 0;
update_time = 0;
train_time  = toc;  
logInfo('Preprocessing took %f sec', train_time);

number_iterations = opts.noTrainingPoints/2;
logInfo('[T%02d] %d training iterations', trialNo, number_iterations);

d = size(KX, 1);
if 0
    % original init for OKH
    W = rand(d, opts.nbits)-0.5;
else
    % LSH init
    W = randn(d, opts.nbits);
    W = W ./ repmat(diag(sqrt(W'*W))',d,1);
end
% NOTE: W_lastupdate keeps track of the last W used to update the hash table
%       W_lastupdate is NOT the W from last iteration
W_lastupdate = W;
H = [];

% bit flips & bits computed
bitflips          = 0;
bitflips_res      = 0;
bits_computed_all = 0;

% HT updates
update_iters = [];
h_ind_array  = [];
%%%%%%%%%%%%%%%%%%%%%%% SET UP OKH %%%%%%%%%%%%%%%%%%%%%%%


%%%%%%%%%%%%%%%%%%%%%%% STREAMING BEGINS! %%%%%%%%%%%%%%%%%%%%%%%
%rX = KX(:,idxTrain); %set being search in testing 
%tX = KX(:,idxTest); %query set in testing
for iter = 1:number_iterations
    
    if ~opts.unsupervised
        idx_i = Ytrain(2*iter-1, :); %idxTrain(dataIdx(2*i-1));
        idx_j = Ytrain(2*iter, :);   %idxTrain(dataIdx(2*i));
        s = 2*(idx_i==idx_j)-1;
    else
	idx_i = [];idx_j = [];
	s = 2*(pdist([Xtrain(2*iter-1,:);Xtrain(2*iter,:)],'euclidean') <= thr_dist) - 1;
    end

    xi = KX(:, 2*iter-1); %KX(:,idx_i);
    xj = KX(:, 2*iter);   %X(:,idx_j);

    % hash function update
    t_ = tic;
    W = OKHlearn(xi,xj,s,W,para);
    train_time = train_time + toc(t_);


    % ---- reservoir update & compute new reservoir hash table ----
    t_ = tic;
    Hres_new = [];
    if reservoir_size > 0
        [reservoir, update_ind] = update_reservoir(reservoir, [xi,xj]', ...
            [idx_i; idx_j], reservoir_size, W_lastupdate, opts.unsupervised);
        % compute new reservoir hash table (do not update yet)
        Hres_new = (W' * reservoir.X' > 0)';
    end

    % ---- determine whether to update or not ----
    [update_table, trigger_val, h_ind] = trigger_update(iter, ...
        opts, W_lastupdate, W, reservoir, Hres_new, ...
		 opts.unsupervised, thr_dist);
    res_time = res_time + toc(t_);

    % ---- hash table update, etc ----
    if update_table
        h_ind_array = [h_ind_array; single(ismember(1:opts.nbits, h_ind))];
        W_lastupdate(:, h_ind) = W(:, h_ind);
        update_iters = [update_iters, iter];

        % update reservoir hash table
        if reservoir_size > 0
            reservoir.H = Hres_new;
            if strcmpi(opts.trigger, 'bf')
                bitflips_res = bitflips_res + trigger_val;
            end
        end

        % actual hash table update (record time)
        t_ = tic;
        [H, bf_all, bits_computed] = update_hash_table(H, W_lastupdate, ...
            KX', Ytrain, h_ind, update_iters, opts);
        bits_computed_all = bits_computed_all + bits_computed;
        bitflips = bitflips + bf_all;
        update_time = update_time + toc(t_);
    end

    % ---- save intermediate model ----
    % CHECKPOINT
    if ismember(iter, test_iters)
        F = sprintf('%s_iter%d.mat', prefix, iter);
        save(F, 'W', 'W_lastupdate', 'H', 'bitflips', 'bits_computed_all', ...
            'train_time', 'update_time', 'res_time', 'update_iters');

        logInfo(['*checkpoint*\n[T%02d] %s\n' ...
            '     (%d/%d) W %.2fs, HT %.2fs(%d updates), Res %.2fs\n' ...
            '     total #BRs=%g, avg #BF=%g'], ...
            trialNo, opts.identifier, iter*opts.batchSize, opts.noTrainingPoints, ...
            train_time, update_time, numel(update_iters), res_time, ...
            bits_computed_all, bitflips);
    end
end
%%%%%%%%%%%%%%%%%%%%%%% STREAMING ENDED! %%%%%%%%%%%%%%%%%%%%%%%

% save final model, etc
F = [prefix '.mat'];
save(F, 'Xanchor', 'sigma', 'W', 'H', 'bitflips', 'bits_computed_all', ...
    'train_time', 'update_time', 'res_time', 'test_iters', 'update_iters', ...
    'h_ind_array');

ht_updates = numel(update_iters);
logInfo('%d Hash Table updates, bits computed: %g', ht_updates, bits_computed_all);
logInfo('[T%02d] Saved: %s\n', trialNo, F);
end


% ---------------------------------------------------------
% ---------------------------------------------------------
function [KX, Xanchor, sigma] = init_okh(Xtrain)
assert(size(Xtrain, 1) >= 4000);

tic;
% sample support samples (300) from the FIRST HALF of training set
nhalf = floor(size(Xtrain, 1)/2);
ind = randperm(nhalf, 300);
Xanchor = Xtrain(ind, :);
logInfo('Randomly selected 300 anchor points');

% estimate sigma for Gaussian kernel using samples from the SECOND HALF
ind = randperm(nhalf, 2000);
Xval = Xtrain(nhalf+ind, :);
Kval = sqdist(Xval', Xanchor');
sigma = mean(mean(Kval, 2));
logInfo('Estimated sigma = %g', sigma);
clear Xval Kval

% preliminary for testing
% kernel mapping the whole set
KX = exp(-0.5*sqdist(Xtrain', Xanchor')/sigma^2)';
KX = [KX; ones(1,size(KX,2))];

end

