package Pod::Weaver::Section::Template;
use Moose;
# ABSTRACT: add pod section from a Text::Template template

with 'Pod::Weaver::Role::Section';

use Text::Template 'fill_in_file';

use Moose::Util::TypeConstraints;

subtype 'PWST::File',
    as 'Str',
    where { !m+^~/+ && -r },
    message { "Couldn't read file $_" };
coerce 'PWST::File',
    from 'Str',
    via { s+^~/+$ENV{HOME}/+; $_ };

no Moose::Util::TypeConstraints;

has template => (
    is       => 'ro',
    isa      => 'PWST::File',
    required => 1,
    coerce   => 1,
);

has header => (
    is      => 'ro',
    isa     => 'Str',
    default => sub { shift->plugin_name },
);

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

sub main_module_name {
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

sub parse_pod {
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

sub get_zilla_hash {
    my $self = shift;
    my ($zilla) = @_;
    my %zilla_hash;
    for my $attr ($zilla->meta->get_all_attributes) {
        next if $attr->get_read_method =~ /^_/;
        my $value = $attr->get_value($zilla);
        $zilla_hash{$attr->name} = blessed($value) ? \$value : $value;
    }
    $zilla_hash{main_module_name} = $self->main_module_name($zilla);
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
            $zilla ? ($self->get_zilla_hash($zilla)) : (),
            %{ $self->extra_args },
        },
    );

    push @{ $document->children },
        Pod::Elemental::Element::Nested->new(
            command  => 'head1',
            content  => $self->header,
            children => $self->parse_pod($pod),
        );
}

__PACKAGE__->meta->make_immutable;
no Moose;

1;
