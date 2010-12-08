package Pod::Weaver::Section::Template;
use Moose;
# ABSTRACT: add pod section from a Text::Template template

with 'Pod::Weaver::Role::Section';

use Text::Template 'fill_in_file';

=head1 SYNOPSIS

  # weaver.ini
  [Template / SUPPORT]
  template = ~/.dzil/pod_templates/support.section
  main_module_only = 1

=head1 DESCRIPTION

This plugin generates a pod section based on the contents of a template file.
The template is parsed using L<Text::Template>, and is then interpreted as pod.
When parsing the template, any options specified in the plugin configuration
which aren't configuration options for this plugin will be provided as
variables for the template. Also, if this is being run as part of a
L<Dist::Zilla> build process, the values of all of the attributes on the
C<zilla> object will be available as variables, and the additional variable
C<$main_module_name> will be defined as the module name for the C<main_module>
file.

=head2 Variables Available in Template from the zilla object

To discover these variables I created a template with the following construct:

{{ use Data::Dumper }}
{{ Dumper $fi_varhash }}

then did the same for each of the top level values reported there.

Each variable is listed with its name and its type in parenthesis.

=over 4

=item * abstract (scalar)

The abstract defined with # ABSTRACT

{{ $abstract }}

=item * authors (array)

An array of scalars containing the authors of the module.

{{ $OUT .= join "\n", @authors }}

=item * built_in

Unknown.

=item * chrome (Dist::Zilla::Chrome::Term)

Doesn't appear to be usable in a template.

=item * distmeta (hash)

=over 4

=item * abstract (scalar)

See C<abstract> elsewhere in this document.

=item * author (array)

See C<authors> elsewhere in this document.

=item * dynamic_config (scalar)

Unknown.

=item * generated_by (scalar)

The version of Dist::Zilla generating this distribution.

=item * license (scalar)

Equivalent to {{ lc $license->meta2_name }}

=item * meta-spec (hash)

Version and url of the meta specification being used.

{{ $distmeta{ 'meta-spec' }{ 'url' } }}

=item * name (scalar)

See C<name> elsewhere in this document.

=item * no_index (hash)

Key is 'directory'.  Contains array of directories (files?) that are not to be
indexed.

=item * provides (hash)

What packages this distribution provides as keys, the hash contains version and
filename.

=item * release_status (scalar)

This distributions release status.

=item * resources (hash)

{{ use Data::Dumper;
   Dumper $distmeta{ 'resources' }
}}

=item * version

See C<version> elsewhere in this document.

=back

=item * files (array of Dist::Zilla::File::?????)

The files to be written out.

{{ $OUT = join "\n", map { $_->name } @files }}

See L<Dist::Zilla::File> for documentation for this object.

=item * is_trial (scalar)

Unknown.

=item * license (Software::License::????)

Whatever you have set your license type to.

{{ $license->meta2_name }}

See L<Software::License> for documentation for this object.

=item * logger (Log::Dispatchouli::Proxy)

Doesn't appear to be usable in a template.

See L<Log::Dispatchouli::Proxy> for documentation for this object.

=item * main_module (Dist::Zilla::File::????)

The name of the file that is being used as the main module file.

{{ $main_module->name }}

See L<Dist::Zilla::File> for documentation for this object.

=item * main_module_name (scalar)

The module name for the C<main_module> file, as described above.

{{ $main_module_name }}

=item * name (scalar)

The package name. I think.

{{ $name }}

=item * prereqs (Dist::Zilla::Prereqs)

Don't know if its usable in a template.

See L<Dist::Zilla::Prereqs> for documentation for this object.

=item * root (Path::Class::Dir)

I believe this is the root directory we are working from.

{{ $root }}

See L<Path::Class::Dir> for documentation for this object.

=item * version (scalar)

The version number for the distribution.

{{ $version }}

=back

=cut

use Moose::Util::TypeConstraints;

subtype 'PWST::File',
    as 'Str',
    where { !m+^~/+ && -r },
    message { "Couldn't read file $_" };
coerce 'PWST::File',
    from 'Str',
    via { s+^~/+$ENV{HOME}/+; $_ };

no Moose::Util::TypeConstraints;

=attr template

The file to be run through Text::Template and added as a pod section. Required.

=cut

has template => (
    is       => 'ro',
    isa      => 'PWST::File',
    required => 1,
    coerce   => 1,
);

=attr header

The section header. Defaults to the plugin name.

=cut

has header => (
    is      => 'ro',
    isa     => 'Str',
    default => sub { shift->plugin_name },
);

=attr main_module_only

If L<Pod::Weaver> is being run through L<Dist::Zilla>, this option determines
whether to add the section to each module in the distribution, or to just the
distribution's main module. Defaults to false.

=cut

has main_module_only => (
    is  => 'ro',
    isa => 'Bool',
);

has delim => (
    is      => 'ro',
    isa     => 'ArrayRef[Str]',
    default => sub { ['{{', '}}'] },
);

has extra_args => (
    is  => 'rw',
    isa => 'HashRef',
);

sub BUILD {
    my $self = shift;
    my ($args) = @_;
    my $copy = {%$args};
    delete $copy->{$_}
        for map { $_->init_arg } $self->meta->get_all_attributes;
    $self->extra_args($copy);
}

sub _main_module_name {
    my $self = shift;
    my ($zilla) = @_;
    return unless $zilla;

    my $main_module_name = $zilla->main_module->name;
    my $root = $zilla->root->stringify;
    $main_module_name =~ s:^\Q$root::;
    $main_module_name =~ s:lib/::;
    $main_module_name =~ s+/+::+g;
    $main_module_name =~ s/\.pm//;

    return $main_module_name;
}

sub _parse_pod {
    my $self = shift;
    my ($pod) = @_;

    # ensure it's a valid pod document
    $pod = "=pod\n\n$pod\n";

    my $children = Pod::Elemental->read_string($pod)->children;

    # but strip off the bits we had to add
    shift @$children
        while $children->[0]->isa('Pod::Elemental::Element::Generic::Blank')
           || ($children->[0]->isa('Pod::Elemental::Element::Generic::Command')
            && $children->[0]->command eq 'pod');
    my $blank;
    $blank = pop @$children
        while $children->[-1]->isa('Pod::Elemental::Element::Generic::Blank');
    push @$children, $blank
        if $blank;

    return $children;
}

sub _get_zilla_hash {
    my $self = shift;
    my ($zilla) = @_;
    my %zilla_hash;
    for my $attr ($zilla->meta->get_all_attributes) {
        next if $attr->get_read_method =~ /^_/;
        my $value = $attr->get_value($zilla);
        $zilla_hash{$attr->name} = blessed($value) ? \$value : $value;
    }
    $zilla_hash{main_module_name} = $self->_main_module_name($zilla);
    return %zilla_hash;
}

sub weave_section {
    my $self = shift;
    my ($document, $input) = @_;

    my $zilla = $input->{zilla};

    if ($self->main_module_only) {
        return if $zilla && $zilla->main_module->name ne $input->{filename};
    }

    die "Couldn't find file " . $self->template
        unless -r $self->template;
    my $pod = fill_in_file(
        $self->template,
        DELIMITERS => $self->delim,
        HASH       => {
            $zilla ? ($self->_get_zilla_hash($zilla)) : (),
            %{ $self->extra_args },
        },
    );

    push @{ $document->children },
        Pod::Elemental::Element::Nested->new(
            command  => 'head1',
            content  => $self->header,
            children => $self->_parse_pod($pod),
        );
}

__PACKAGE__->meta->make_immutable;
no Moose;

=head1 SEE ALSO

L<Text::Template>
L<Pod::Weaver>
L<Dist::Zilla>

=begin Pod::Coverage

  BUILD
  weave_section

=end Pod::Coverage

=cut

1;
