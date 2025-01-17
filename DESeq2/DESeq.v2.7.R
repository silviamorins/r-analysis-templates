# Analysis pipeline from raw read count table to differential expression lists using DESeq2
# Author: Stefan Czemmel
# Contributors: Gisela Gabernet
# MIT License

#load necessary libs
if (!require("RColorBrewer")){
  source("http://bioconductor.org/biocLite.R")
  biocLite("RColorBrewer", suppressUpdates=TRUE)
  library("RColorBrewer")
}
if (!require("reshape2")){
  source("http://bioconductor.org/biocLite.R")
  biocLite("reshape2", suppressUpdates=TRUE)
  library("reshape2")
}
if (!require("genefilter")){
  source("https://bioconductor.org/biocLite.R")
  biocLite("genefilter")
  library("genefilter")
}
if (!require("DESeq2")){
  source("https://bioconductor.org/biocLite.R")
  biocLite("DESeq2")
  library("DESeq2")
}
if (!require("ggplot2")){
  source("https://bioconductor.org/biocLite.R")
  biocLite("ggplot2")
  library("ggplot2")
}
if (!require("plyr")){
  source("https://bioconductor.org/biocLite.R")
  biocLite("plyr")
  library("plyr")
}
if (!require("vsn")){
  source("https://bioconductor.org/biocLite.R")
  biocLite("vsn")
  library("vsn")
}
if (!require("gplots")){
  source("https://bioconductor.org/biocLite.R")
  biocLite("gplots")
  library("gplots")
}
if (!require("pheatmap")){
  source("https://bioconductor.org/biocLite.R")
  biocLite("pheatmap")
  library("pheatmap")
}



#clean up
rm(list = ls(all = TRUE)) # clear all variables
graphics.off()

theme_set(theme_classic())

######################################
# create directories needed
ifelse(!dir.exists("DESeq2"), dir.create("DESeq2"), FALSE)
dir.create("DESeq2/raw_counts")
dir.create("DESeq2/results")
dir.create("DESeq2/metadata")
dir.create("DESeq2/results/plots")
dir.create("DESeq2/results/plots/plots_example_genes")
dir.create("DESeq2/results/plots/plots_requested_genes")
dir.create("DESeq2/results/tables")
dir.create("DESeq2/results/final")
######################################

#1)check input data path
#path_count_table = "input/merged_gene_counts.txt"
#metadata_path <- "input/Sample_preparations.tsv"
#path_design <- "input/design.txt"
#path_contrasts <- "input/contrasts.tsv"
#requested_genes_path <- "input/requested_genes.txt"
## provide these files as arguments:
args = commandArgs(trailingOnly=TRUE)
if (length(args)<3) {
   stop("Three arguments must be supplied (merged gene counts, sample preparations sheet and design - OPTIONALS: list of contrasts and requested genes).\n", call.=FALSE)
}
path_count_table = args[1]
metadata_path <- args[2]
path_design <- args[3]
path_contrasts <- args[4]
requested_genes_path <- args[5]


##2) load count table
### Modified from csv to tsv, NA strings NA

count.table <- read.table(path_count_table,  header = T,sep = "\t",na.strings =c("","NA"),quote=NULL,stringsAsFactors=F,dec=".",fill=TRUE,row.names=1)
## Need to remove gene names column
count.table$Ensembl_ID <- row.names(count.table)
drop <- c("Ensembl_ID","gene_name")
gene_names <- count.table[,drop]
count.table <- count.table[ , !(names(count.table) %in% drop)]
##Need to reduce gene names to QBiC codes
names(count.table) <- gsub('([A-Z0-9]{10})\\Aligned\\.(.*)\\.(.*)','\\1', names(count.table))
write.table(count.table , file = "DESeq2/raw_counts/raw_counts.txt", append = FALSE, quote = FALSE, sep = "\t",eol = "\n", na = "NA", dec = ".", row.names = F,  col.names = T, qmethod = c("escape", "double"))

###2.1) remove lines with "__" from HTSeq, not needed for featureCounts (will not harm here)
count.table <- count.table[!grepl("^__",row.names(count.table)),]
#do some hard filtering just based on number of 0's per row
count.table = count.table[rowSums(count.table)>0,]

###3) load metadata: sample preparations tsv file from qPortal

system(paste("cp ",metadata_path," DESeq2/metadata/",sep=""))
m <- read.table(metadata_path, sep="\t", header=TRUE,na.strings =c("","NaN"),quote=NULL,stringsAsFactors=F,dec=".",fill=TRUE,row.names = 1)


#make sure m is factor where needed
names(m) = gsub("Condition..","condition_",names(m))
conditions = names(m)[grepl("condition_",names(m))]
sapply(m,class)
for (i in conditions) {
  m[,i] = as.factor(m[,i])
}
sapply(m,class)


## Need to order columns in count.table
count.table <- count.table[, order(names(count.table))]

#check m and count table sorting, (correspond to QBiC codes): if not in the same order stop
stopifnot(identical(names(count.table),row.names(m)))

#change row.names now:
m$Secondary.Name <- gsub(" ; ", "_", m$Secondary.Name)
m$nn = paste(row.names(m),m$Secondary.Name,sep="_")
names(count.table) = m$nn
row.names(m) = m$nn

stopifnot(identical(names(count.table),row.names(m)))


#to get all possible pairwise comparisons, make a combined factor

conditions <- grepl(colnames(m),pattern = "condition_")
m$x <- apply(m[ ,conditions],1,paste, collapse = "_")


###4) run DESeq function
design <- read.csv(path_design, sep="\t", header = F)
cds <- DESeqDataSetFromMatrix( countData =count.table, colData =m, design = eval(parse(text=as.character(design[[1]]))))
cds <- DESeq(cds,  parallel = TRUE)


### 4.1) sizeFactors(cds) as indicator of library sequencing depth
sizeFactors(cds)
write.table(sizeFactors(cds),paste("DESeq2/results/tables/sizeFactor_libraries.tsv",sep=""), append = FALSE, quote = FALSE, sep = "\t",eol = "\n", na = "NA", dec = ".", row.names = T,  col.names = F, qmethod = c("escape", "double"))

#write raw counts to file
write.table(count.table, paste("DESeq2/results/tables/raw.read.counts.tsv",sep=""), append = FALSE, quote = FALSE, sep = "\t",eol = "\n", na = "NA", dec = ".", row.names = T,  col.names = NA, qmethod = c("escape", "double"))
#write log2 counts to file
log2counts <- log2(assay(cds)+0.1)
write.table(log2counts, paste("DESeq2/results/tables/log2counts.tsv",sep=""), append = FALSE, quote = FALSE, sep = "\t",eol = "\n", na = "NA", dec = ".", row.names = T,  col.names = NA, qmethod = c("escape", "double"))

###4.2) contrasts
coefficients <- resultsNames(cds)
contrasts <- read.table(path_contrasts, sep="\t", header = T)
stopifnot(length(coefficients)==ncol(contrasts))

bg = data.frame(bg = character(nrow(cds)))

## Contrast calculation
for (i in c(1:ncol(contrasts))) {
  d1 <-results(cds, contrast=contrasts[[i]])
  contname <- names(contrasts[i])
  d1 <- as.data.frame(d1)
  print(contname)
  d1_name <- d1
  d1_name$Ensembl_ID = row.names(d1)
  d1_name <- merge(x=d1_name, y=gene_names, by.x = "Ensembl_ID", by.y="Ensembl_ID", all.x=T)
  d1_name = d1_name[,c(dim(d1_name)[2],1:dim(d1_name)[2]-1)]
  d1_name = d1_name[order(d1_name[,"Ensembl_ID"]),]
  d1DE <- subset(d1_name, padj < 0.05)
  write.table(d1DE, file=paste("DESeq2/results/tables/DE_contrast_",contname,".tsv",sep=""), sep="\t", quote=F, col.names = T, row.names = F)
  names(d1) = paste(names(d1),contname,sep="_")
  bg = cbind(bg,d1)
}


#remove identical columns
bg$bg <- NULL
idx <- duplicated(t(bg))
bg <- bg[, !idx]
bg$Ensembl_ID <- row.names(bg)
bg <- bg[,c(dim(bg)[2],1:dim(bg)[2]-1)]
names(bg)[1:2] = c("Ensembl_ID","baseMean")
names(bg)



#4.3) get DE genes from any contrast
padj=names(bg)[grepl("padj",names(bg))]

padj = bg[,padj]
padj[is.na(padj)] <- 1
padj = ifelse(padj < 0.05, 1, 0)
padj = as.data.frame(padj)
cols <- names(padj)
padj$filter <- apply(padj[ ,cols],1,paste, collapse = "-")
padj$Ensembl_ID = row.names(padj)
padj = padj[,c("Ensembl_ID","filter")]

#make final data frame
bg1 = merge(bg,padj,by.x="Ensembl_ID",by.y="Ensembl_ID")
stopifnot(identical(dim(bg1)[1],dim(assay(cds))[1]))
bg1$filter1 = ifelse(grepl("1",bg1$filter),"DE","not_DE")
bg1 = merge(x=bg1, y=gene_names, by.x="Ensembl_ID", by.y="Ensembl_ID", all.x = T)
bg1 = bg1[,c(dim(bg1)[2],1:dim(bg1)[2]-1)]
bg1 = bg1[order(bg1[,"Ensembl_ID"]),]

#4.4) extract ID for genes to plot, make 20 plots:
kip <- subset(bg1, filter1 == "DE")
kip = unique(kip$Ensembl_ID)


if (length(kip) > 20) {
  set.seed(10)
  kip1 = sample(kip,size = 2)
} else {
  kip1 = kip
  }

for (i in kip1){
  d <- plotCounts(cds, gene=i, intgroup=c("x"), returnData=TRUE,normalized = T)
  d$variable = row.names(d)
  plot <- ggplot(data=d, aes(x=x, y=count, fill=x)) +
            geom_boxplot(position=position_dodge()) +
            geom_jitter(position=position_dodge(.8)) +
            facet_grid(cols= vars(x)) +
            ggtitle(paste("Gene ",i,sep="")) + xlab("") + ylab("Normalized gene counts") + theme_bw() +
            theme(text = element_text(size=12),
               axis.text.x = element_text(angle=45, vjust=1,hjust=1))
  ggsave(filename=paste("DESeq2/results/plots/plots_example_genes/",i,".png",sep=""), width=10, height=5, plot=plot)
  print(i)
}

#4.5) make plots of interesting genes
gene_ids <- read.table(requested_genes_path, col.names = "requested_gene_name")
gene_ids$requested_gene_name <- sapply(gene_ids$requested_gene_name, toupper)
bg1$gene_name <- sapply(bg1$gene_name, toupper)

kip2 <- subset(bg1, gene_name %in% gene_ids$requested_gene_name)
kip2_Ensembl <- kip2$Ensembl_ID
kip2_gene_name <- kip2$gene_name
for (i in c(1:length(kip2_Ensembl)))
{
  d <- plotCounts(cds, gene=kip2_Ensembl[i], intgroup=c("x"), returnData=TRUE,normalized = T)
  d$variable = row.names(d)
  plot <- ggplot(data=d, aes(x=x, y=count, fill=x)) +
    geom_boxplot(position=position_dodge()) +
    geom_jitter(position=position_dodge(.8)) +
    facet_grid(cols= vars(x)) +
    ggtitle(paste("Gene ",kip2_gene_name[i],sep="")) + xlab("") + ylab("Normalized gene counts") + theme_bw() +
    theme(text = element_text(size=12),
          axis.text.x = element_text(angle=45, vjust=1,hjust=1))
  ggsave(filename=paste("DESeq2/results/plots/plots_requested_genes/",kip2_gene_name[i],"_",kip2_Ensembl[i],".png",sep=""), width=10, height=5, plot=plot)
  print(kip2_gene_name[i])
}

#write to file
write.table(bg1, "DESeq2/results/final/final_list_DESeq2.tsv", append = FALSE, quote = FALSE, sep = "\t",eol = "\n", na = "NA", dec = ".", row.names = F,  col.names = T, qmethod = c("escape", "double"))

###5) Data transformation
#rlog
rld <- rlog(cds)
##vst
vsd <- varianceStabilizingTransformation(cds)

#write normalized values to a file
write.table(assay(rld), "DESeq2/results/tables/rlog_transformed.read.counts.tsv", append = FALSE, quote = FALSE, sep = "\t",eol = "\n", na = "NA", dec = ".", row.names = TRUE,  col.names = NA, qmethod = c("escape", "double"))
write.table(assay(vsd), "DESeq2/results/tables/vst_transformed.read.counts.tsv", append = FALSE, quote = FALSE, sep = "\t",eol = "\n", na = "NA", dec = ".", row.names = TRUE,  col.names = NA, qmethod = c("escape", "double"))


#################
##6) Diagnostic plots

#Cooks distances: get important for example when checking knock-out and overexpression studies
pdf("DESeq2/results/plots/Cooks-distances.pdf")
par(mar=c(10,3,3,3))
par( mfrow = c(1,2))
boxplot(log10(assays(cds)[["cooks"]]), range=0, las=2,ylim = c(-15, 15),main="log10-Cooks")
boxplot(log2(assays(cds)[["cooks"]]), range=0, las=2,ylim = c(-15, 15),main="log2-Cooks")
dev.off()

#The function plotDispEsts visualizes DESeqs dispersion estimates: 
pdf("DESeq2/results/plots/Dispersion_plot.pdf")
plotDispEsts(cds, ylim = c(1e-5, 1e8))
dev.off()

#Effects of transformations on the variance
notAllZero <- (rowSums(counts(cds))>0) 
pdf("DESeq2/results/plots/Effects_of_transformations_on_the_variance.pdf")
par(oma=c(3,3,3,3))
par(mfrow = c(1, 3))
meanSdPlot(log2(counts(cds,normalized=TRUE)[notAllZero,] + 1),ylab  = "sd raw count data")
meanSdPlot(assay(rld[notAllZero,]),ylab  = "sd rlog transformed count data")
meanSdPlot(assay(vsd[notAllZero,]),ylab  = "sd vst transformed count data")
dev.off()
# 
# level1 = levels(cds[["x"]])[1]
# level1 = which(cds[["x"]] == level1)
# level2 = levels(cds[["x"]])[2]
# level2 = which(cds[["x"]] == level2)
# 
# #Scatter plot -- effect of trafo
# pdf("DESeq2/results/plots/scatter_plot_effect_of_transformation.pdf")
# par( mfrow = c(1,2)) 
# plot( log2( 1+counts(cds, normalized=TRUE)[, level1[1]:level2[1]]), col="#00000020", pch=20, cex=0.3,main="log2 count data")
# plot( assay(rld)[,level1[1]:level2[1]], col="#00000020", pch=20, cex=0.3,main="rlog transformed count data" )
# dev.off()


###Sample distances
sampleDists <- dist(t(assay(rld)))
sampleDistMatrix <- as.matrix(sampleDists)
#rownames(sampleDistMatrix) <- paste(colnames(rld),rld$x, sep="-")
#colnames(sampleDistMatrix) <- paste(colnames(rld),rld$x, sep="-")
colours = colorRampPalette(rev(brewer.pal(9, "Blues")))(255) 

### Visualization of distance using Heatmaps
pdf("DESeq2/results/plots/Heatmaps_of_distances.pdf")
par(oma=c(3,3,3,3))
pheatmap(sampleDistMatrix, clustering_distance_rows=sampleDists, clustering_distance_cols=sampleDists, col=colours,fontsize=6)
dev.off()

png("DESeq2/results/plots/Heatmaps_of_distances.png", width=15, height=15, units="cm",res=300)
#par(oma=c(3,3,3,3))
pheatmap(sampleDistMatrix, clustering_distance_rows=sampleDists, clustering_distance_cols=sampleDists, col=colours,fontsize=6)
dev.off()



 #### Visualization of distance using PCA plots
#pdf("DESeq2/results/plots/PCA_plot_of_distances.pdf")
pcaData <- plotPCA(rld,intgroup=c("x"),ntop = dim(rld)[1], returnData=TRUE)
percentVar <- round(100*attr(pcaData, "percentVar"))
pca <- ggplot(pcaData, aes(PC1, PC2, color=x)) +
  geom_point(size=3) +
  xlab(paste0("PC1: ",percentVar[1],"% variance")) +
  ylab(paste0("PC2: ",percentVar[2], "% variance")) +
  coord_fixed()
ggsave(plot = pca, filename = "DESeq2/results/plots/PCA_plot.pdf", device = "pdf", dpi = 300)
ggsave(plot = pca, filename = "DESeq2/results/plots/PCA_plot.png", device = "png", dpi = 150)
#dev.off()

#"own"approach
#dat1 <- plotPCA(rld, intgroup=c("x"), returnData=TRUE,ntop = dim(rld)[1])
#percentVar <- round(100 * attr(dat1, "percentVar"))

#pdf("DESeq2/results/plots/PCA_plot_of_distances_new.pdf")
#ggplot(dat1, aes(PC1, PC2, color=x)) + 
#  geom_point(size=3) + 
#  xlab(paste0("PC1: ",percentVar[1],"% variance")) + 
#  ylab(paste0("PC2: ",percentVar[2],"% variance")) + 
#  coord_fixed()
#dev.off()

###Gene clustering
topVarGenes <- head(order(rowVars(assay(rld)), decreasing=TRUE), 50)
pdf("DESeq2/results/plots/heatmap_of_top50_genes_with_most_variance_across_samples.pdf")
par(oma=c(3,3,3,3))
heatmap.2(assay(rld)[topVarGenes, ],scale="row",trace="none",dendrogram="col",col=colorRampPalette( rev(brewer.pal(9, "RdBu")))(255),cexRow=0.5,cexCol=0.5)
#take out labCol=paste(colnames(rld),rld$genetic_background, sep="--")
dev.off()

png("DESeq2/results/plots/heatmap_of_top50_genes_with_most_variance_across_samples.png", width=20, height=20, units="cm",res=300)
par(oma=c(3,3,3,3))
heatmap.2(assay(rld)[topVarGenes, ],scale="row",trace="none",dendrogram="col",col=colorRampPalette( rev(brewer.pal(9, "RdBu")))(255),cexRow=0.5,cexCol=0.5)
#take out labCol=paste(colnames(rld),rld$genetic_background, sep="--")
dev.off()



#further diagnostics plots
dir.create("DESeq2/results/plots/further_diagnostics")
res=0
for (i in resultsNames(cds)[-1]) {
  res = results(cds,name = i)
  pdf(paste("DESeq2/results/plots/further_diagnostics/all_results_MA_plot_",i,".pdf",sep=""))
  plotMA(res,ylim = c(-4, 4))
  dev.off()
  #multiple hyptothesis testing
  qs <- c( 0, quantile(results(cds)$baseMean[res$baseMean > 0], 0:4/4 ))
  bins <- cut(res$baseMean, qs )
  # rename the levels of the bins using the middle point
  levels(bins) <- paste0("~",round(.5*qs[-1] + .5*qs[-length(qs)]))
  # 3) calculate the ratio of p values less than .01 for each bin
  ratios <- tapply(res$pvalue, bins, function(p) mean(p < .01, na.rm=TRUE ))
  # 4) plot these ratios
  pdf(paste("DESeq2/results/plots/further_diagnostics/dependency_small.pval_mean_normal.counts_",i,".pdf",sep=""))
  barplot(ratios, xlab="mean normalized count", ylab="ratio of small p values")
  dev.off()
  #plot number of rejections
  pdf(paste("DESeq2/results/plots/further_diagnostics/number.of.rejections_",i,".pdf",sep=""))
  plot(metadata(res)$filterNumRej,
       type="b", ylab="number of rejections",
       xlab="quantiles of filter")
  lines(metadata(res)$lo.fit, col="red")
  abline(v=metadata(res)$filterTheta)
  dev.off()
  #Histogram of passed and rejected hypothesis for contrast ctnnb1 vs control liver
  use <- res$baseMean > metadata(res)$filterThreshold
  table(use)
  h1 <- hist(res$pvalue[!use], breaks=0:50/50, plot=FALSE)
  h2 <- hist(res$pvalue[use], breaks=0:50/50, plot=FALSE)
  colori <- c('do not pass'="khaki", 'pass'="powderblue")
  pdf(paste("DESeq2/results/plots/further_diagnostics/histogram_of_p.values",i,".pdf",sep=""))
  barplot(height = rbind(h1$density, h2$density), beside = FALSE,
          col = colori, space = 0, main = "", xlab="p value",ylab="frequency")
  text(x = c(0, length(h1$counts)), y = 0, label = paste(c(0,1)),
       adj = c(0.5,1.7), xpd=NA)
  legend("topleft", fill=rev(colori), legend=rev(names(colori)))
  dev.off()
  rm(res,qs,bins,ratios,use,h1,h2,colori)
}

#save data
save.image("DESeq2/DESeq2.RData")



#end of script
####-------------save Sessioninfo
fn <- paste("DESeq2/sessionInfo_",format(Sys.Date(), "%d_%m_%Y"),".txt",sep="")
sink(fn)
sessionInfo()
sink()
####---------END----save Sessioninfo 




