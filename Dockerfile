from sequenceiq/hadoop-docker:latest

RUN yum -y install git wget
RUN git clone https://github.com/DSC-SPIDAL/harp.git
RUN sed -i -- 's/<module>harp-daal-app<\/module>/<!-- <module>harp-daal-app<\/module> -->/' harp/pom.xml
RUN curl -s -L http://mirrors.koehn.com/apache/maven/maven-3/3.5.0/binaries/apache-maven-3.5.0-bin.tar.gz > apache-maven-3.5.0-bin.tar.gz; \
	    tar xzf apache-maven-3.5.0-bin.tar.gz; \
	    mv apache-maven-3.5.0 /opt; \
	    ln -s /opt/apache-maven-3.5.0 /opt/maven; \
	    rm -rf apache-maven-3.5.0-bin.tar.gz
ENV PATH /opt/maven/bin:$PATH
RUN wget -q --no-cookies --no-check-certificate --header "Cookie: gpw_e24=http%3A%2F%2Fwww.oracle.com%2F; oraclelicense=accept-securebackup-cookie" "http://download.oracle.com/otn-pub/java/jdk/8u152-b16/aa0333dd3019491ca4f6ddbe78cdb6d0/jdk-8u152-linux-x64.rpm" && \
	    yum -y localinstall jdk-8u152-linux-x64.rpm && \
	    rm -rf jdk-8u152-linux-x64.rpm
RUN cd harp && mvn clean package
ENV HADOOP_HOME /usr/local/hadoop
RUN cp harp/harp-project/target/harp-project-1.0-SNAPSHOT.jar $HADOOP_HOME/share/hadoop/mapreduce/ \
	    && cp harp/third_party/fastutil-7.0.13.jar $HADOOP_HOME/share/hadoop/mapreduce/
COPY mapred-site.xml $HADOOP_HOME/etc/hadoop/mapred-site.xml
RUN cp harp/harp-app/target/harp-app-1.0-SNAPSHOT.jar $HADOOP_HOME
RUN wget https://github.com/01org/daal/releases/download/2018/l_daal_oss_p_2018.0.013.tgz && \
	    tar xzf l_daal_oss_p_2018.0.013.tgz && \
	    mv l_daal_oss_p_2018.0.013 /opt/daal && \
	    rm -rf l_daal_oss_p_2018.0.013.tgz
ENV PATH /opt/daal/bin:$PATH
RUN yum -y install centos-release-scl-rh devtoolset-3-gcc-c++ devtoolset-3-gcc 
#scl enable devtoolset-3 bash
ENV PATH /opt/rh/devtoolset-3/root/usr/bin:$PATH

ENV ICC_PATH /parallel_studio_xe_2016_update4
RUN wget http://registrationcenter-download.intel.com/akdlm/irc_nas/tec/9781/parallel_studio_xe_2016_update4.tgz && \
	    tar xzf parallel_studio_xe_2016_update4.tgz && \
	    rm -rf parallel_studio_xe_2016_update4.tgz && \
	    sed -i -- 's/ACTIVATION_TYPE=exist_lic/ACTIVATION_TYPE=trial_lic/' /$ICC_PATH/silent.cfg && \
	    sed -i -- 's/ACCEPT_EULA=decline/ACCEPT_EULA=accept/' /$ICC_PATH/silent.cfg && \
	    bash /$ICC_PATH/install.sh --silent /$ICC_PATH/silent.cfg && \
	    echo $ICC_PATH && \
	    rm -rf /parallel_studio_xe_2016_update4
RUN cd /harp && git submodule update --init --recursive 
ENV PATH /opt/intel/bin:$PATH
RUN source /opt/intel/bin/compilervars.sh intel64 
ENV CPATH $JAVA_HOME/include/linux:$JAVA_HOME/include:$CPATH
RUN yum -y install libstdc++-devel
RUN source /opt/intel/bin/compilervars.sh intel64 && cd /harp/harp-daal-app/daal-src && git checkout daal_2018_beta && git pull && cat makefile.lst && make daal PLAT=lnx32e -j 16
RUN sed -i -- 's/<!-- <module>harp-daal-app<\/module> -->/<module>harp-daal-app<\/module>/' /harp/pom.xml
RUN source /harp/harp-daal-app/__release__lnx/daal/bin/daalvars.sh intel64 && cd /harp/ && mvn clean package
## setup additional env vars needed by DAAL native
ENV HARP_DAAL_HOME /harp/harp-daal-app
ENV TBBROOT ${HARP_DAAL_HOME}/daal-src/externals/tbb
# copy harp-daal-app jar file to Hadoop directory
RUN cp ${HARP_DAAL_HOME}/target/harp-daal-app-1.0-SNAPSHOT.jar ${HADOOP_HOME}
# put daal and tbb, omp libs to hdfs, they will be loaded into the distributed cache of 
# running harp mappers
ENV PATH $HADOOP_HOME/bin:$PATH
#ENV LIBJARS ${DAALROOT}/lib/daal.jar
RUN /etc/bootstrap.sh && \
	    source /opt/intel/bin/compilervars.sh intel64 && \
	    hdfs dfsadmin -safemode leave && \
	    hdfs dfs -mkdir -p /Hadoop/Libraries && \
	    hdfs dfs -put ${DAALROOT}/lib/intel64_lin/libJavaAPI.so /Hadoop/Libraries/ && \
	    hdfs dfs -put ${TBBROOT}/lib/intel64/gcc4.4/libtbb* /Hadoop/Libraries/ && \
	    hdfs dfs -put ${HARP_DAAL_HOME}/external/omp/libiomp5.so /Hadoop/Libraries/

RUN wget -q https://repo.continuum.io/archive/Anaconda2-5.0.1-Linux-x86_64.sh -O /conda.sh && \
	    bash /conda.sh -b -p /opt/conda && \
	    rm /conda.sh
ENV PATH /opt/conda/bin:$PATH
RUN conda install -y numpy=1.13.1 scipy=0.19.1 scikit-learn=0.19.0 matplotlib=2.0.2 pillow=3.2.0 && \
			   pip --no-cache-dir install scikit-surprise 
COPY movielens_nytimes.tar.gz /
RUN tar xzf /movielens_nytimes.tar.gz -C / && \
	    rm /movielens_nytimes.tar.gz && \
	    /etc/bootstrap.sh && \
	    hdfs dfsadmin -safemode leave && \
	    hdfs dfs -mkdir -p /movielens/movielens-test && \
	    hdfs dfs -mkdir -p /movielens/movielens-train && \
	    hdfs dfs -mkdir -p /nytimes && \
	    hdfs dfs -put /dataset/nytimes/nytimes.mrlda /nytimes/ && \
	    hdfs dfs -put /dataset/movielens/movielens-test.mm /movielens/movielens-test/ && \
	    hdfs dfs -put /dataset/movielens/movielens-train.mm /movielens/movielens-train/
#ENV DAALROOT /opt/intel/compilers_and_libraries_2016.4.258/linux/daal
ENV DAALROOT /harp/harp-daal-app/__release__lnx/daal/
ENV HARP_DAAL_ROOT /harp/harp-daal-app
ENV PYTHONPATH /harp/harp-daal-python
ENV HARP_JAR $HADOOP_HOME/harp-app-1.0-SNAPSHOT.jar
ENV HARP_DAAL_JAR $HADOOP_HOME/harp-daal-app-1.0-SNAPSHOT.jar
# Updating harp
RUN cd harp && git pull && mvn clean package && \
	    cp /harp/harp-app/target/harp-app-1.0-SNAPSHOT.jar $HADOOP_HOME
