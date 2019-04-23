module Capistrano
  module Asg
    # Extend AWS Resource class to include AMI methods
    class AMI < AWSResource
      attr_reader :region_config
      include Taggable

      def self.create(region_config = {}, &_block)
        ami = new(region_config)
        ami.cleanup do
          ami.save
          ami.tag 'deployed-with' => 'cap-asg'
          ami.tag 'cap-asg-deploy-group' => ami.autoscaling_group_name
          yield ami
        end
      end

      def initialize(region_config = {})
        @region_config = region_config
      end

      def save
        info "Creating EC2 AMI from EC2 Instance: #{base_ec2_instance.id}"
        ec2_instance = ec2_resource.instance(base_ec2_instance.id)
        @aws_counterpart = ec2_instance.create_image(
          name: name,
          no_reboot: region_config.fetch(:aws_no_reboot_on_create_ami, true)
        )
      end

      def destroy(images = [])
        images.each do |i|
          info "Deleting old AMI: #{i.id}"
          snapshots = snapshots_attached_to i
          i.deregister
          delete_snapshots snapshots
        end
      end

      private

      def name
        timestamp region_config.fetch(:aws_ami_name_prefix, "latest-#{environment}-AMI")
      end

      def trash
        ec2_resource.images(owners: ['self']).to_a.select do |ami|
          deployed_with_asg? ami
        end
      end

      def snapshots_attached_to(image)
        ids = image.block_device_mappings.map(&:ebs).compact.map(&:snapshot_id)
        ec2_resource.snapshots(snapshot_ids: ids)
      end

      def delete_snapshots(snapshots)
        snapshots.each do |snapshot|
          info "Deleting snapshot: #{snapshot.id}"
          snapshot.delete unless snapshot.nil?
        end
      end
    end
  end
end
