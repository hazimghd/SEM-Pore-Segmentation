 
clc;
clear;
close all;

fprintf('========================================\n');
fprintf('   Pore Detection System - Enhanced v2\n');
fprintf('========================================\n\n');

%% =========================
% Settings
%% =========================
imageDir     = fullfile(pwd,'images');
maskDir      = fullfile(pwd,'masks');
inputSize    = [256 256];
inputSizeNet = [256 256 3];

% ---- Training Parameters ----
params.learningRate = 5e-4;
params.epochs       = 200;   % Modified to 200 Epochs
params.batchSize    = 8;
params.pixelWeight  = [1 10];
params.dropPeriod   = 15;
params.dropFactor   = 0.5;

% ---- Post-Processing Parameters ----
pp.morphCloseR = 2;
pp.morphOpenR  = 1;
pp.minArea     = 20;
pp.maxArea     = 8000;
pp.confThresh  = 0.45;

rng(1);

%% =========================
% Read Dataset
%% =========================
if ~isfolder(imageDir)
    error('Image folder does not exist');
end

if ~isfolder(maskDir)
    error('Mask folder does not exist');
end

imageFiles = dir(fullfile(imageDir,'*.tif'));
if isempty(imageFiles)
    imageFiles = dir(fullfile(imageDir,'*.png'));
end

maskFiles = dir(fullfile(maskDir,'*.tif'));
if isempty(maskFiles)
    maskFiles = dir(fullfile(maskDir,'*.png'));
end

names = intersect(string({imageFiles.name}), string({maskFiles.name}));

imagePaths = fullfile(imageDir, names);
maskPaths  = fullfile(maskDir, names);

N = numel(names);
fprintf('Number of images = %d\n\n', N);

%% =========================
% Dataset Splitting
%% =========================
idx = randperm(N);

nTrain = round(0.7*N);
nVal   = round(0.15*N);

trainImages = imagePaths(idx(1:nTrain));
trainMasks  = maskPaths(idx(1:nTrain));

valImages = imagePaths(idx(nTrain+1:nTrain+nVal));
valMasks  = maskPaths(idx(nTrain+1:nTrain+nVal));

testImages = imagePaths(idx(nTrain+nVal+1:end));
testMasks  = maskPaths(idx(nTrain+nVal+1:end));

%% =========================
% Datastore Creation
%% =========================
dsTrain = arrayDatastore((1:numel(trainImages))',...
    'IterationDimension',1);

dsVal = arrayDatastore((1:numel(valImages))',...
    'IterationDimension',1);

trainDs = transform(dsTrain,...
    @(x) readDataFixed(x,trainImages,trainMasks,inputSize,true));

valDs = transform(dsVal,...
    @(x) readDataFixed(x,valImages,valMasks,inputSize,false));

%% =========================
% DeepLabV3+ Network
%% =========================
lgraph = deeplabv3plusLayers(inputSizeNet, 2, "resnet18");

pxLayer = pixelClassificationLayer(...
    'Name','labels',...
    'Classes',["background","pore"],...
    'ClassWeights',params.pixelWeight);

lgraph = replaceLayer(lgraph,'classification',pxLayer);

%% =========================
% Training Options
%% =========================
options = trainingOptions('adam',...
    'InitialLearnRate',      params.learningRate,...
    'LearnRateSchedule',     'piecewise',...
    'LearnRateDropFactor',   params.dropFactor,...
    'LearnRateDropPeriod',   params.dropPeriod,...
    'MaxEpochs',             params.epochs,...
    'MiniBatchSize',         params.batchSize,...
    'Shuffle',               'every-epoch',...
    'ValidationData',        valDs,...
    'ValidationFrequency',   20,...
    'ValidationPatience',    Inf,...   % Early stopping disabled
    'Verbose',               true,...
    'VerboseFrequency',      10,...
    'Plots',                 'training-progress');

fprintf('Training started...\n');

net = trainNetwork(trainDs, lgraph, options);

fprintf('Training completed successfully ✅\n');

%% =========================
% Save Trained Model
%% =========================
save('trained_model_200Epoch.mat','net');

disp('Model saved successfully');

%% =========================
% Functions
%% =========================
function dataOut = readDataFixed(idx, imagePaths, maskPaths, inputSize, augment)

    i = idx{1};

    % Read image and mask
    img  = imread(imagePaths{i});
    mask = imread(maskPaths{i});

    % Convert RGB to grayscale if necessary
    if size(img,3)==3
        img = rgb2gray(img);
    end

    if size(mask,3)==3
        mask = rgb2gray(mask);
    end

    % Resize image and mask
    img  = imresize(img,  inputSize);
    mask = imresize(mask, inputSize, 'nearest');

    % Convert mask to binary
    mask = mask > 0;

    %% Data Augmentation
    if augment

        % Horizontal flip
        if rand > 0.5
            img  = fliplr(img);
            mask = fliplr(mask);
        end

        % Vertical flip
        if rand > 0.5
            img  = flipud(img);
            mask = flipud(mask);
        end

        % Random rotation
        k = randi([0 3]);
        img  = rot90(img, k);
        mask = rot90(mask, k);
    end

    %% Preprocessing
    img = im2single(img);

    % CLAHE contrast enhancement
    img = adapthisteq(img);

    % Convert grayscale to 3-channel image
    img = cat(3, img, img, img);

    %% Convert mask to categorical labels
    C = categorical(mask,[0 1],["background","pore"]);

    dataOut = {img, C};
end
